#!/usr/bin/env python3
"""Static contracts for Floci Fluent Bit; renders manifests but never contacts clusters."""
from __future__ import annotations

from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]


def render(path: str) -> list[dict]:
    completed = subprocess.run(
        ["kubectl", "kustomize", str(ROOT / path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return [item for item in yaml.safe_load_all(completed.stdout) if item]


class FlociFluentBitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.full_overlay = render("infra/kubernetes/overlays/floci")
        cls.observability = render("infra/kubernetes/overlays/floci-observability")
        cls.disabled = render("infra/kubernetes/overlays/floci-observability-disabled")

    def test_floci_overlay_unschedules_kind_selector_and_uses_local_endpoint(self) -> None:
        ds = next(item for item in self.full_overlay if item.get("kind") == "DaemonSet" and item["metadata"]["name"] == "aws-for-fluent-bit")
        pod_spec = ds["spec"]["template"]["spec"]
        self.assertEqual(pod_spec.get("nodeSelector", {}), {})
        config = next(item for item in self.full_overlay if item.get("kind") == "ConfigMap" and item["metadata"]["name"] == "aws-for-fluent-bit")["data"]
        self.assertIn("endpoint              http://172.27.0.2:4566", config["fluent-bit.conf"])
        self.assertIn("Name                  cloudwatch", config["fluent-bit.conf"])
        self.assertNotIn("Name                  kubernetes", config["fluent-bit.conf"])

    def test_cloudwatch_egress_is_only_floci_and_port_4566(self) -> None:
        policy = next(item for item in self.observability if item.get("kind") == "NetworkPolicy")
        rule = policy["spec"]["egress"]
        self.assertEqual(rule, [{
            "to": [{"ipBlock": {"cidr": "172.27.0.2/32"}}],
            "ports": [{"protocol": "TCP", "port": 4566}],
        }])

    def test_activation_overlay_contains_only_observability_resources(self) -> None:
        identities = {(item["kind"], item["metadata"]["name"]) for item in self.observability}
        self.assertEqual(identities, {
            ("ServiceAccount", "aws-for-fluent-bit"),
            ("ConfigMap", "aws-for-fluent-bit"),
            ("DaemonSet", "aws-for-fluent-bit"),
            ("NetworkPolicy", "fluent-bit-cloudwatch-egress"),
        })

    def test_daemonset_is_nonroot_has_no_token_or_kubernetes_rbac(self) -> None:
        ds = next(item for item in self.observability if item.get("kind") == "DaemonSet")
        pod_spec = ds["spec"]["template"]["spec"]
        container = pod_spec["containers"][0]
        self.assertFalse(pod_spec["automountServiceAccountToken"])
        self.assertTrue(pod_spec["securityContext"]["runAsNonRoot"])
        self.assertTrue(container["securityContext"]["runAsNonRoot"])
        self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
        self.assertFalse(container["securityContext"].get("privileged", False))
        self.assertFalse(any(item.get("kind") in {"Role", "RoleBinding", "ClusterRole", "ClusterRoleBinding"} for item in self.observability))
        self.assertFalse(any("serviceAccountToken" in str(volume) for volume in pod_spec.get("volumes", [])))

    def test_existing_log_groups_and_json_fields_are_preserved(self) -> None:
        source = (ROOT / "packages/shared-observability/src/index.ts").read_text()
        config = next(item for item in self.observability if item.get("kind") == "ConfigMap" and item["metadata"]["name"] == "aws-for-fluent-bit")["data"]["fluent-bit.conf"]
        for field in ("timestamp", "level", "event", "service", "environment", "correlation_id", "service_group"):
            self.assertIn(field, source)
        self.assertIn("Name                  cloudwatch", config)
        self.assertIn("endpoint              http://172.27.0.2:4566", config)
        self.assertIn("log_group_name        /aegisvolt/${AEGISVOLT_ENV}/$(service_group)", config)
        self.assertIn("auto_create_group     false", config)
        self.assertIn("Regex                 $correlation_id .+", config)
        self.assertIn("Regex                 $service_group ^(graphql-gateway|station-reservation|billing-wallet|energy-dispatch)$", config)

    def test_compose_endpoint_address_matches_verified_floci_network(self) -> None:
        compose = (ROOT / "compose.floci.yaml").read_text()
        self.assertIn("subnet: 172.27.0.0/16", compose)
        self.assertIn("gateway: 172.27.0.1", compose)
        self.assertIn("ipv4_address: 172.27.0.2", compose)

    def test_rollback_overlay_restores_kind_unscheduled_behavior(self) -> None:
        ds = next(item for item in self.disabled if item.get("kind") == "DaemonSet")
        self.assertEqual(
            ds["spec"]["template"]["spec"]["nodeSelector"],
            {"aegisvolt.io/cloudwatch": "enabled"},
        )
        self.assertTrue(any(item.get("kind") == "NetworkPolicy" for item in self.disabled))

    def test_kustomize_local_copies_match_their_sources(self) -> None:
        base = (ROOT / "infra/kubernetes/base/fluent-bit.yaml").read_bytes()
        egress = (ROOT / "infra/kubernetes/overlays/floci-observability/fluent-bit-egress.yaml").read_bytes()
        for directory in ("floci-observability", "floci-observability-disabled"):
            self.assertEqual((ROOT / f"infra/kubernetes/overlays/{directory}/fluent-bit-base.yaml").read_bytes(), base)
        self.assertEqual((ROOT / "infra/kubernetes/overlays/floci/fluent-bit-egress.yaml").read_bytes(), egress)
        self.assertEqual((ROOT / "infra/kubernetes/overlays/floci-observability-disabled/fluent-bit-egress.yaml").read_bytes(), egress)
        for name in (
            "fluent-bit-config.patch.yaml",
            "fluent-bit-security.patch.yaml",
            "fluent-bit-serviceaccount.patch.yaml",
        ):
            self.assertEqual(
                (ROOT / "infra/kubernetes/overlays/floci" / name).read_bytes(),
                (ROOT / "infra/kubernetes/overlays/floci-observability" / name).read_bytes(),
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

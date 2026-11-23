import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


class FlociCICDTests(unittest.TestCase):
    def test_environment_resolver_allows_only_pr_and_push_targets(self):
        script = ROOT / "scripts/floci-environment.sh"
        for event in ("pr", "push"):
            for env in ("dev", "test", "prod"):
                result = subprocess.run(["bash", str(script), event, env], capture_output=True, text=True)
                self.assertEqual((result.returncode, result.stdout.strip()), (0, env))
        for args in (("pr", "main"), ("push", "feature/foo"), ("push", "prod;touch /tmp/pwned")):
            result = subprocess.run(["bash", str(script), *args], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)

    def test_pr_and_push_workflows_are_separate_and_environment_scoped(self):
        pr = yaml.load((ROOT / ".github/workflows/floci-plan.yml").read_text(), Loader=yaml.BaseLoader)
        push = yaml.load((ROOT / ".github/workflows/floci-apply.yml").read_text(), Loader=yaml.BaseLoader)
        self.assertEqual(pr["on"]["pull_request"]["branches"], ["dev", "test", "prod"])
        self.assertEqual(push["on"]["push"]["branches"], ["dev", "test", "prod"])
        plan = pr["jobs"]["terraform-plan"]
        apply = push["jobs"]["terraform-apply"]
        self.assertIn("head.repo.full_name == github.repository", plan["if"])
        self.assertIn("author_association", plan["if"])
        self.assertIn("aegisvolt-floci", plan["runs-on"])
        self.assertIn("aegisvolt-floci", apply["runs-on"])
        self.assertIn("github.base_ref", plan["environment"])
        self.assertIn("github.ref_name", apply["environment"])
        self.assertNotIn("terraform apply", str(plan).lower())
        self.assertIn("floci-ci-terraform.sh apply", str(apply))
        self.assertNotIn("aws-actions/configure-aws-credentials", str(pr) + str(push))
        self.assertNotIn("docker", str(pr).lower() + str(push).lower())

    def test_plan_does_not_apply_and_uses_only_selected_workspace(self):
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            fake = temp / "terraform"
            log = temp / "calls"
            fake.write_text("""#!/usr/bin/env python3
import json, os, sys
a=sys.argv[1:]
if a and a[0].startswith('-chdir='): a=a[1:]
with open(os.environ['MOCK_TF_LOG'],'a') as f: f.write(' '.join(a)+'\\n')
if a[:2] == ['show','-json']: print(json.dumps({'resource_changes':[]}))
elif 'plan' in a:
 p=a[a.index('-out=')+1] if '-out=' in a else None
 if p: open(p,'w').write('saved-plan')
elif a and a[0]=='init': pass
sys.exit(0)
""")
            fake.chmod(0o755)
            env = os.environ.copy()
            env.update({"PATH": f"{temp}:{env['PATH']}", "MOCK_TF_LOG": str(log)})
            env.pop("AWS_ACCESS_KEY_ID", None)
            env.pop("AWS_SECRET_ACCESS_KEY", None)
            run = subprocess.run(["bash", str(ROOT / "scripts/floci-ci-terraform.sh"), "plan", "test"],
                                 cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            calls = log.read_text()
            self.assertIn("workspace select test", calls)
            self.assertNotIn("workspace select dev", calls)
            self.assertNotIn(" apply ", f" {calls} ")

    def test_apply_rejects_aws_credentials_before_terraform(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["PATH"] = f"{tmp}:{env['PATH']}"
            env["AWS_SESSION_TOKEN"] = "real-looking-session"
            env.pop("AWS_SECRET_ACCESS_KEY", None)
            result = subprocess.run(["bash", str(ROOT / "scripts/floci-ci-terraform.sh"), "apply", "dev"],
                                    cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 78)
            self.assertIn("AWS_SESSION_TOKEN", result.stderr)

    def test_ruleset_keeps_current_checks_and_only_adds_observed_floci_context_on_request(self):
        text = (ROOT / "scripts/github-rulesets.sh").read_text()
        self.assertIn('"type": "deletion"', text)
        self.assertIn('"type": "non_fast_forward"', text)
        self.assertIn('"type": "pull_request"', text)
        self.assertIn('FLOCI_PLAN_REQUIRED_CONTEXT', text)
        self.assertIn("no se modificó GitHub", text)
        self.assertIn("  terraform-plan:", (ROOT / ".github/workflows/ci.yml").read_text())


if __name__ == "__main__":
    unittest.main()

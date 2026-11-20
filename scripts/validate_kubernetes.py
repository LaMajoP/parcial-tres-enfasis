#!/usr/bin/env python3
"""Validación estática sin clúster: sintaxis YAML y contratos mínimos de EKS."""
from __future__ import annotations

from pathlib import Path
import sys
import yaml

ROOT = Path("infra/kubernetes")
errors: list[str] = []
documents: list[tuple[Path, dict]] = []

for path in sorted(ROOT.rglob("*.yaml")):
    try:
        for document in yaml.safe_load_all(path.read_text(encoding="utf-8")):
            if document:
                if not isinstance(document, dict):
                    errors.append(f"{path}: documento YAML no es un objeto")
                else:
                    documents.append((path, document))
    except yaml.YAMLError as exc:
        errors.append(f"{path}: YAML inválido: {exc}")

rollouts = [doc for _, doc in documents if doc.get("kind") == "Rollout"]
if len(rollouts) != 1:
    errors.append(f"Se esperaba exactamente un Rollout y se encontraron {len(rollouts)}")
else:
    rollout = rollouts[0]
    canary = rollout.get("spec", {}).get("strategy", {}).get("canary", {})
    if canary.get("stableService") != "graphql-gateway-stable" or canary.get("canaryService") != "graphql-gateway-canary":
        errors.append("El Rollout no referencia los Services stable/canary esperados")
    if not any(step.get("setWeight") == 20 for step in canary.get("steps", []) if isinstance(step, dict)):
        errors.append("El Rollout no define canary de tráfico al 20 %")
    if "alb" not in canary.get("trafficRouting", {}):
        errors.append("El Rollout base no declara tráfico ALB ponderado")

for path, document in documents:
    text = path.read_text(encoding="utf-8")
    if "REPLACE_" in text:
        errors.append(f"{path}: contiene placeholder desplegable REPLACE_")
    if document.get("kind") in {"Deployment", "Rollout"}:
        spec = document.get("spec", {}).get("template", {}).get("spec", {})
        for container in spec.get("containers", []):
            image = container.get("image", "")
            if not image:
                errors.append(f"{path}: contenedor sin image")
            if not container.get("resources"):
                errors.append(f"{path}: contenedor {container.get('name')} sin requests/limits")

if errors:
    print("VALIDACIÓN KUBERNETES FALLÓ", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    sys.exit(1)
print(f"Kubernetes estático válido: {len(documents)} documentos, Rollout 20/80 y sin placeholders desplegables.")

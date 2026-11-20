#!/usr/bin/env python3
"""Chequeo local de invariantes de Actions cuando actionlint no está instalado."""
from __future__ import annotations

from pathlib import Path
import sys
import yaml


def load(path: str) -> dict:
    # BaseLoader mantiene la clave YAML 1.1 `on` como texto.
    value = yaml.load(Path(path).read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    if not isinstance(value, dict):
        raise ValueError(f"{path} no contiene un workflow YAML")
    return value


errors: list[str] = []
ci = load(".github/workflows/ci.yml")
deploy = load(".github/workflows/deploy.yml")
build = load(".github/workflows/build-release-images.yml")

ci_on = ci.get("on", {})
if sorted(ci_on.get("pull_request", {}).get("branches", [])) != ["dev", "prod", "test"]:
    errors.append("CI debe dispararse solo para PR con destino dev, test o prod")
for job in ("lockfile", "image-build", "terraform-plan"):
    if job not in ci.get("jobs", {}):
        errors.append(f"CI debe contener el job {job}")

branches = deploy.get("on", {}).get("push", {}).get("branches", [])
if sorted(branches) != ["dev", "prod", "test"]:
    errors.append("CD no debe reaccionar a main ni feature/*")
if "self-hosted" not in deploy.get("jobs", {}).get("infrastructure", {}).get("runs-on", []):
    errors.append("Infraestructura debe requerir runner privado self-hosted")
if "build_dev_images" not in deploy.get("jobs", {}):
    errors.append("CD debe construir imágenes una sola vez tras merge a dev")
if "workflow_dispatch" not in build.get("on", {}):
    errors.append("La construcción de imágenes debe ser controlada por workflow_dispatch")

if errors:
    print("VALIDACIÓN DE WORKFLOWS FALLÓ", file=sys.stderr)
    print("\n".join(f"- {item}" for item in errors), file=sys.stderr)
    sys.exit(1)
print("Workflows estáticos válidos: PR por rama destino, CD solo dev/test/prod y runner privado para EKS.")

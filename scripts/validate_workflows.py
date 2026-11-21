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


def steps(job: dict) -> str:
    return "\n".join(str(step.get("run", "")) for step in job.get("steps", []))


errors: list[str] = []
ci = load(".github/workflows/ci.yml")
deploy = load(".github/workflows/deploy.yml")
build = load(".github/workflows/build-release-images.yml")
ci_jobs = ci.get("jobs", {})
deploy_jobs = deploy.get("jobs", {})

ci_on = ci.get("on", {})
if sorted(ci_on.get("pull_request", {}).get("branches", [])) != ["dev", "prod", "test"]:
    errors.append("CI debe dispararse solo para PR con destino dev, test o prod")

for job in (
    "promotion-policy", "lockfile", "lint-build", "unit-tests", "integration-tests",
    "resilience-tests", "e2e-tests", "image-build", "terraform-offline", "terraform-plan",
):
    if job not in ci_jobs:
        errors.append(f"CI debe contener el job {job}")

promotion = steps(ci_jobs.get("promotion-policy", {}))
for expected in ("feature/", 'test "${SOURCE_BRANCH#feature/}" != "$SOURCE_BRANCH"', 'test "$SOURCE_BRANCH" = "dev"', 'test "$SOURCE_BRANCH" = "test"'):
    if expected not in promotion:
        errors.append("promotion-policy debe restringir feature/* → dev → test → prod")

for job in ("lint-build", "unit-tests", "integration-tests", "resilience-tests", "e2e-tests"):
    if "npm ci" not in steps(ci_jobs.get(job, {})):
        errors.append(f"{job} debe instalar con npm ci")
if "npm run test:integration" not in steps(ci_jobs.get("integration-tests", {})):
    errors.append("integration-tests debe ejecutar pruebas reales de integración")
if "npm run test:resilience" not in steps(ci_jobs.get("resilience-tests", {})):
    errors.append("resilience-tests debe ejecutar pruebas reales de resiliencia")
if "npx playwright install --with-deps chromium" not in steps(ci_jobs.get("e2e-tests", {})):
    errors.append("e2e-tests debe instalar Chromium de Playwright")
if "docker compose down -v" not in steps(ci_jobs.get("integration-tests", {})):
    errors.append("integration-tests debe limpiar sus recursos efímeros")

offline = steps(ci_jobs.get("terraform-offline", {}))
for expected in ("validate_workflows.py", "validate_kubernetes.py", "npm run terraform:validate"):
    if expected not in offline:
        errors.append("terraform-offline debe ejecutar validaciones sin AWS")

plan = ci_jobs.get("terraform-plan", {})
plan_if = str(plan.get("if", ""))
for expected in ("head.repo.fork == false", "vars.TF_PLAN_ENABLED == 'true'"):
    if expected not in plan_if:
        errors.append("terraform-plan debe excluir forks y requerir TF_PLAN_ENABLED")
plan_steps = steps(plan)
plan_step_names = "\n".join(str(step.get("name", "")) for step in plan.get("steps", []))
if "Exigir configuración real del Environment" not in plan_step_names:
    errors.append("terraform-plan debe validar las variables reales del Environment")
for variable in ("AWS_ROLE_ARN", "AWS_REGION", "TF_STATE_BUCKET", "TF_OWNER", "VPC_CIDRS_JSON", "AVAILABILITY_ZONES_JSON"):
    if variable not in plan_steps:
        errors.append(f"terraform-plan debe requerir {variable}")
if " plan " not in plan_steps or " show " not in plan_steps:
    errors.append("terraform-plan debe ejecutar un plan real y publicar su representación")
if "workspace new" in plan_steps or "workspace select" not in plan_steps:
    errors.append("terraform-plan no debe crear workspaces durante un PR")

branches = deploy.get("on", {}).get("push", {}).get("branches", [])
if sorted(branches) != ["dev", "prod", "test"]:
    errors.append("CD no debe reaccionar a main ni feature/*")
infrastructure = deploy_jobs.get("infrastructure", {})
if "self-hosted" not in infrastructure.get("runs-on", []):
    errors.append("Infraestructura debe requerir runner privado self-hosted")
if "vars.CD_ENABLED == 'true'" not in str(infrastructure.get("if", "")):
    errors.append("CD debe quedar bloqueado hasta activar explícitamente CD_ENABLED")
if "build_dev_images" not in deploy_jobs:
    errors.append("CD debe construir imágenes una sola vez tras merge a dev")
if " apply -auto-approve" not in steps(infrastructure):
    errors.append("CD debe conservar el apply explícito, detrás del gate CD_ENABLED")
if "workflow_dispatch" not in build.get("on", {}):
    errors.append("La construcción de imágenes debe ser controlada por workflow_dispatch")
if "vars.CD_ENABLED == 'true'" not in str(build.get("jobs", {}).get("build-and-push", {}).get("if", "")):
    errors.append("La construcción manual de imágenes debe respetar CD_ENABLED")

deployment_script = Path("scripts/deploy-kubernetes.sh").read_text(encoding="utf-8")
if "@sha256" not in deployment_script or "kubectl apply -k" not in deployment_script:
    errors.append("El despliegue debe aplicar únicamente digests inmutables mediante Kustomize")
if "kubectl argo rollouts" in deployment_script:
    errors.append("El despliegue no debe depender del plugin cliente de Argo Rollouts")
if "condition=Healthy rollout/graphql-gateway" not in deployment_script:
    errors.append("El despliegue debe esperar el estado Healthy del Rollout")

if errors:
    print("VALIDACIÓN DE WORKFLOWS FALLÓ", file=sys.stderr)
    print("\n".join(f"- {item}" for item in errors), file=sys.stderr)
    sys.exit(1)
print("Workflows estáticos válidos: PR protegido, pruebas reales, plan AWS condicional y CD bloqueado hasta CD_ENABLED.")

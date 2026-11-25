"""Flows operativos: consultan salud y auditan datos durables; no generan métricas ficticias."""
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

import boto3
from prefect import flow, get_run_logger, task

ENVIRONMENTS = ("dev", "test", "prod")
DEFAULT_GATEWAYS = {"dev": "http://graphql-gateway:4000", "test": "http://graphql-gateway:4000", "prod": "http://graphql-gateway:4000"}


def _now() -> datetime:
    return datetime.now(timezone.utc)


@task(retries=2, retry_delay_seconds=5, timeout_seconds=10)
def gateway_health(environment: str, gateway_url: str) -> dict[str, Any]:
    """Verifica /health/ready real y conserva la respuesta para el run de Prefect."""
    try:
        with urlopen(f"{gateway_url}/health/ready", timeout=8) as response:  # nosec B310: URL de configuración controlada
            payload = json.loads(response.read().decode("utf-8"))
            return {"environment": environment, "ok": response.status == 200, "status": response.status, "payload": payload}
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        return {"environment": environment, "ok": False, "error": str(error)}


def _dynamo(environment: str):
    endpoint = os.getenv("DYNAMODB_ENDPOINT")
    kwargs: dict[str, Any] = {"region_name": os.getenv("AWS_REGION", "us-east-2")}
    if endpoint:
        kwargs.update(endpoint_url=endpoint, aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "local"), aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "local"))
    return boto3.resource("dynamodb", **kwargs).Table(os.getenv("TABLE_SAGA", f"aegisvolt-saga-{environment}"))


def find_saga_anomalies(records: list[dict[str, Any]], max_age_minutes: int = 10) -> list[dict[str, Any]]:
    """Clasifica SAGAs durables atascadas y compensaciones pendientes sin mutar datos."""
    threshold = _now().timestamp() - max_age_minutes * 60
    anomalies: list[dict[str, Any]] = []
    active_states = {"PENDING", "RESERVED", "CHARGED", "ACTIVATING", "COMPENSATING", "COMPENSATION_FAILED"}
    for record in records:
        if record.get("state") not in active_states:
            continue
        try:
            updated_at = datetime.fromisoformat(str(record["updatedAt"]).replace("Z", "+00:00")).timestamp()
        except (KeyError, TypeError, ValueError):
            anomalies.append({"saga_id": record.get("sagaId", "unknown"), "kind": "MALFORMED_TIMESTAMP", "state": record.get("state")})
            continue
        if record["state"] == "COMPENSATION_FAILED":
            anomalies.append({"saga_id": record.get("sagaId"), "kind": "COMPENSATION_FAILED", "state": record["state"]})
        elif updated_at < threshold:
            anomalies.append({"saga_id": record.get("sagaId"), "kind": "STUCK_SAGA", "state": record["state"], "updated_at": record["updatedAt"]})
    return anomalies


def summarize_sagas(records: list[dict[str, Any]], anomalies: list[dict[str, Any]]) -> dict[str, int]:
    """Summarize terminal compensated/failed SAGAs and active orphan candidates."""
    counts = {"compensated": 0, "failed": 0, "orphaned": 0}
    for record in records:
        if record.get("state") == "COMPENSATED":
            counts["compensated"] += 1
        elif record.get("state") == "COMPENSATION_FAILED":
            counts["failed"] += 1
    counts["orphaned"] = sum(item.get("kind") == "STUCK_SAGA" for item in anomalies)
    return counts


@task(retries=2, retry_delay_seconds=5, timeout_seconds=30)
def audit_dynamodb(environment: str) -> dict[str, Any]:
    table = _dynamo(environment)
    records: list[dict[str, Any]] = []
    scan_kwargs: dict[str, Any] = {"FilterExpression": "begins_with(PK, :prefix)", "ExpressionAttributeValues": {":prefix": "SAGA#"}}
    while True:
        page = table.scan(**scan_kwargs)
        records.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        scan_kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    anomalies = find_saga_anomalies(records)
    return {"environment": environment, "table": table.name, "scanned": len(records),
            "saga_counts": summarize_sagas(records, anomalies), "anomalies": anomalies}


@task
def publish_audit_summary(health: dict[str, Any], audit: dict[str, Any]) -> dict[str, Any]:
    logger = get_run_logger()
    summary = {
        "environment": audit["environment"], "health_ok": health["ok"],
        "health_status": health.get("status", "UNAVAILABLE"),
        "sagas_scanned": audit["scanned"], "saga_counts": audit["saga_counts"],
        "anomaly_count": len(audit["anomalies"]), "anomalies": audit["anomalies"]
    }
    logger.info(json.dumps(summary))
    if summary["anomaly_count"]:
        logger.warning("Se detectaron SAGAs para reconciliación: %s", json.dumps(audit["anomalies"]))
    return summary


@flow(name="aegisvolt-health-and-saga-audit", log_prints=True)
def health_and_saga_audit(environment: str = "dev", gateway_url: str | None = None) -> dict[str, Any]:
    if environment not in ENVIRONMENTS:
        raise ValueError("environment debe ser dev, test o prod")
    url = gateway_url or os.getenv(f"GATEWAY_URL_{environment.upper()}", DEFAULT_GATEWAYS[environment])
    health = gateway_health(environment, url)
    audit = audit_dynamodb(environment)
    return publish_audit_summary(health, audit)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", choices=ENVIRONMENTS, default=os.getenv("AEGISVOLT_ENV", "dev"))
    parser.add_argument("--gateway-url")
    args = parser.parse_args()
    print(json.dumps(health_and_saga_audit(environment=args.environment, gateway_url=args.gateway_url), default=str))

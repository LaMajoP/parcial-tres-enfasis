from datetime import datetime, timedelta, timezone

from flows import find_saga_anomalies, summarize_sagas


def test_audits_successful_compensated_and_orphaned_sagas():
    now = datetime.now(timezone.utc)
    records = [
        {"sagaId": "success", "state": "COMPLETED", "updatedAt": now.isoformat()},
        {"sagaId": "compensated", "state": "COMPENSATED", "updatedAt": now.isoformat()},
        {"sagaId": "orphan", "state": "CHARGED", "updatedAt": (now - timedelta(minutes=11)).isoformat()},
        {"sagaId": "failed-compensation", "state": "COMPENSATION_FAILED", "updatedAt": now.isoformat()},
    ]
    anomalies = find_saga_anomalies(records, max_age_minutes=10)
    assert {item["saga_id"] for item in anomalies} == {"orphan", "failed-compensation"}
    assert summarize_sagas(records, anomalies) == {"compensated": 1, "failed": 1, "orphaned": 1}

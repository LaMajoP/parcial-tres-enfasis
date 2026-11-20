# ADR-0001 — SAGA orquestada durable

**Decisión:** el gateway conserva el estado de la SAGA en DynamoDB y ordena reserva, débito y activación.

**Razón:** la compensación tiene orden obligatorio (reembolso y luego liberación) y debe explicarse/auditarse fácilmente. Coreografía agregaría coordinación implícita.

**Consecuencias:** el gateway es un componente crítico, mitigado con persistencia antes/después de efectos, idempotencia, reconciliación, timeout, retry y circuit breaker. No se implementa Transactional Outbox ni se afirma lo contrario.

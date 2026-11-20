# ADR-0002 — Tablas por contexto y ambiente

**Decisión:** cada servicio posee una tabla DynamoDB por ambiente y solo el rol IRSA del servicio accede a su ARN.

**Trade-off:** se duplican tablas y permisos, pero se evita acoplar despliegues y que GraphQL modifique datos de dominio. `saga` y `flags` pertenecen a SagaCoordination.

# ADR-0007 — Perfil local por defecto

**Decisión:** Compose+DynamoDB Local es el recorrido de desarrollo por defecto. AWS se crea solo tras aprobación de presupuesto.

**Consecuencia:** se preserva evidencia funcional sin producir cargos; EKS, NLB/ALB, endpoints Interface y NAT pueden costar incluso sin tráfico.

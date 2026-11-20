# ADR-0006 — Canary de tráfico, no de réplicas

**Decisión:** Argo Rollouts con ALB weighted target groups inicia 20/80 y consulta métricas CloudWatch de error y p95. Muestra insuficiente se convierte en fallo (`IF requests <= 20, 1`), no en éxito.

**Límite:** Kind permite validar manifiestos/controlador, no CloudWatch ni ALB real. La prueba ponderada real requiere AWS.

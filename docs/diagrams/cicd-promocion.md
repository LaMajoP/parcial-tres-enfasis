# Promoción

```mermaid
flowchart LR
F[feature/* desde dev] -->|PR + checks| D[dev]
D -->|PR + mismo digest| T[test]
T -->|PR + aprobación prod| P[prod]
P --> R[Argo Rollouts 20/80 → AnalysisRun → 100% o abort]
```

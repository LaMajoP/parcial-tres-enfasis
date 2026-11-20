# ADR-0005 — Flags persistentes por ambiente

**Decisión:** flags en tabla `aegisvolt-flags-<env>`, caché de cinco segundos invalidada tras escritura. `prod` exige `platform-admin`.

**Consecuencia:** los cambios son efectivos sin redeploy y no cruzan tablas. La UI actualiza por polling; no se sacrifica aislamiento para simplificar la demo.

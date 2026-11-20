# ADR-0004 — API privada y VPC Link no son lo mismo

**Decisión:** REST API privada restringida por `aws:SourceVpce`, conectada a NLB interno por VPC Link. El `execute-api` Interface Endpoint es para invocadores dentro de VPC.

**Riesgo:** una URL privada no sirve directamente a un navegador público. La demo usa VPN/túnel/host autorizado; el acceso público opcional necesita un entrypoint autenticado separado.

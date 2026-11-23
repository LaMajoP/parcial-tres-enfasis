# Revisión manual de hotspots SonarQube Cloud — Floci local

## HTTP hacia Floci en `scripts/floci-eks-deploy.sh`

Marcar como **Safe** los hotspots que señalan
`http://${floci_ip}:4566` y la variable `floci_dynamodb_endpoint`.

Justificación verificable:

- Floci 2.5.0 expone la API AWS emulada por HTTP y no ofrece TLS en el puerto
  `4566`; cambiarlo a HTTPS rompería el laboratorio sin aportar cifrado.
- `floci_ip` no procede de usuarios ni de red pública: se obtiene mediante
  `docker inspect` de `aegisvolt-floci` en `aegisvolt-floci-net`.
- Docker publica el control-plane sólo como `127.0.0.1:4567`; los Pods llegan
  por una red Docker privada y las NetworkPolicies autorizan exactamente
  `${floci_ip}/32:4566`.
- No hay secretos reales: las credenciales son las literales ficticias `floci`.

No marcar como Safe hallazgos equivalentes fuera de estos scripts locales ni
en providers/backends de producción.

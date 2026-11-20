# Evidencias por capturar tras despliegue real

1. `terraform workspace list` mostrando `dev`, `test`, `prod` y consola S3 > versiones de `env:/<env>/aegisvolt.tfstate`.
2. Salida de `aws ec2 describe-vpc-endpoints` para S3, DynamoDB, Logs y `execute-api`; DNS desde una instancia/pod privado.
3. `kubectl get pods,svc,networkpolicy -n aegisvolt-test` y pruebas de probes.
4. PR a `dev` con checks, artifact de plan y protección de ruleset; terminal mostrando rechazo de push/force-push remoto.
5. Historial de promoción `dev → test → prod`, con environment approval de prod y digest igual en cada etapa.
6. `kubectl argo rollouts get rollout ...` y `AnalysisRun` sano y defectuoso/abortado; distribución 20/80 por métricas del balanceador.
7. UI en éxito, falta de saldo y fallo de hardware, más JSON GraphQL con `saga_id` y `correlation_id`.
8. Logs Insights con el mismo `correlation_id` en gateway y los tres servicios; dashboard CloudWatch.
9. Dashboard Prefect mostrando un run normal y una SAGA huérfana/compensación fallida detectada.
10. Cambio de flag dev y consulta de flag prod sin cambio.

No sustituir estas evidencias por capturas fabricadas o logs copiados manualmente.

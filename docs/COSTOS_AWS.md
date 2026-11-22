# Costos, riesgos y apagado

## Riesgos de costo

EKS cobra plano de control por hora; nodos EC2, NLB/ALB, Interface VPC Endpoints, NAT Gateway (si se habilita), ECR, CloudWatch Logs/métricas, transferencia y un runner privado pueden facturar aunque haya poco tráfico. Producción con dos AZ incrementa disponibilidad y costo. La estimación exacta depende de región, tipos, uso y precios vigentes: usar AWS Pricing Calculator y un AWS Budget antes de `apply`.

## Perfiles

| Perfil | Uso | Costo AWS |
|---|---|---|
| Compose + DynamoDB Local | Desarrollo/demo inicial | Ninguno de AWS |
| Kind | Validación de manifiestos/controlador local | Ninguno de AWS; consume equipo local |
| AWS laboratorio | VPC/EKS/VPCE/API privados | Costos continuos y variables |
| AWS producción | Dos AZ, retención mayor, alertas | Mayor costo, aislamiento fuerte |

El perfil actual evita NAT por defecto y declara endpoints necesarios para ECR, STS, CloudWatch Logs, EC2, EKS, Elastic Load Balancing, execute-api y OIDC de EKS. Cada endpoint de interfaz se cobra por AZ y por datos; el ahorro de NAT no implica costo cero. No habilite la API privada hasta contar con NLB interno verificable, VPN/host de prueba y presupuesto. El detalle de fases está en [TERRAFORM_AWS_PRIMER.md](TERRAFORM_AWS_PRIMER.md).

## Recursos del primer apply por ambiente

| Recurso | Configuración declarada | Riesgo/costo a revisar |
|---|---|---|
| EKS | Plano de control privado, Kubernetes 1.35 | Cargo horario; un upgrade a soporte extendido añade costo. |
| Nodos | Managed node group AL2023, mínimo 2 `t3.medium`, máximo 4 | Dos instancias desde el primer apply, más EBS, transferencia y escalamiento. |
| VPC Endpoints | S3/DynamoDB gateway y 9 interfaces: Logs, execute-api, ECR API/DKR, STS, EC2, ELB, EKS, OIDC EKS | Cada endpoint de interfaz se cobra por AZ; con dos AZ son múltiples ENI facturables por ambiente. |
| DynamoDB | Cinco tablas on-demand | PITR se habilita fuera de `lab_profile`; revisar retención, requests y almacenamiento. |
| CloudWatch | Cinco log groups, métricas, dashboard y alarma | Ingesta, retención y métricas personalizadas crecen con pods y telemetría. |
| ECR compartido | Cinco repositorios inmutables, escaneo y retención de 30 imágenes | Almacenamiento y escaneo; se crea una vez por cuenta, no por workspace. |
| ALB/NLB y API Gateway | ALB/NLB por controlador; API privada solo en segunda fase | Cargos horarios/datos; no active la segunda fase sin NLB interno y pruebas privadas. |

Antes de cualquier apply, estime **un ambiente**, no los tres simultáneamente. `dev`, `test` y `prod` crean VPC/EKS/endpoints/tables aislados; aplicar los tres multiplica los costos recurrentes.

## Apagado seguro

1. Capture evidence y confirme que ningún integrante necesita el laboratorio.
2. Ejecute `terraform plan -destroy` en el workspace correcto y revise especialmente EKS, NLB, endpoints y datos DynamoDB.
3. Solicite aprobación explícita del dueño/cuenta; no use `-auto-approve` para destruir.
4. Ejecute `terraform destroy` solo en el workspace aprobado.
5. Conserve el bucket de state y sus versiones hasta cerrar el curso; destruirlo primero impide administrar recursos restantes.
6. Revise Billing, Cost Explorer y Budgets al día siguiente.

El repositorio no ejecuta ni autoriza `terraform apply`/`destroy` por sí solo.

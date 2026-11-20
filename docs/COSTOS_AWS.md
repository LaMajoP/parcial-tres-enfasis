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

El perfil actual evita NAT por defecto y declara endpoints necesarios; los Interface VPCE y los balanceadores siguen teniendo costo. No habilite la API privada hasta contar con NLB interno verificable, VPN/host de prueba y presupuesto.

## Apagado seguro

1. Capture evidence y confirme que ningún integrante necesita el laboratorio.
2. Ejecute `terraform plan -destroy` en el workspace correcto y revise especialmente EKS, NLB, endpoints y datos DynamoDB.
3. Solicite aprobación explícita del dueño/cuenta; no use `-auto-approve` para destruir.
4. Ejecute `terraform destroy` solo en el workspace aprobado.
5. Conserve el bucket de state y sus versiones hasta cerrar el curso; destruirlo primero impide administrar recursos restantes.
6. Revise Billing, Cost Explorer y Budgets al día siguiente.

El repositorio no ejecuta ni autoriza `terraform apply`/`destroy` por sí solo.

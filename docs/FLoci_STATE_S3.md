# State Terraform local en S3 de Floci

## Backend preparado

`infra/terraform/local-floci/backend.s3.tf.example` configura únicamente el
endpoint de Floci (`http://127.0.0.1:4567`), bucket
`aegisvolt-floci-terraform-state`, `workspace_key_prefix = "env"` y lockfile
S3 (`use_lockfile = true`). El state del bootstrap permanece local en
`local-floci-bootstrap`; no se migra ni comparte.

Terraform deriva los objetos de workspace así:

| Workspace | Objeto de state | Lock |
|---|---|---|
| dev | `env/dev/terraform.tfstate` | `env/dev/terraform.tfstate.tflock` |
| test | `env/test/terraform.tfstate` | `env/test/terraform.tfstate.tflock` |
| prod | `env/prod/terraform.tfstate` | `env/prod/terraform.tfstate.tflock` |

## Preflight no destructivo

```bash
bash scripts/floci-state-migrate.sh preflight
```

Comprueba states locales, lineages únicos, salud de Floci, bucket, versionado
`Enabled` y que el bucket esté vacío antes de la migración. No inicializa el
backend ni escribe objetos. No ejecutar `migrate` hasta autorizarlo y obtener
`PREFLIGHT OK`.

## Evidencia de migración confirmada — 2026-11-23

Según la verificación ejecutada en la terminal del operador, el state se
migró al bucket S3 de Floci con versionado habilitado. No se usó AWS real y
el bootstrap se mantuvo separado. Los backups y states originales se
conservaron. Durante `init -migrate-state`, Terraform incrementó el serial
una vez; lineages y recursos permanecieron iguales.

| Workspace | Lineage | Serial remoto | Recursos | Plan |
|---|---|---:|---:|---|
| dev | `866b3622-720a-51f3-52f9-fbe6ca390181` | 143 | 37 | `No changes` |
| test | `38bd6a3b-1ced-a795-8abf-09732c74281a` | 71 | 36 | `No changes` |
| prod | `457bf529-74b4-9772-080c-c5c694f3f96e` | 68 | 36 | `No changes` |

Esta evidencia procede de la terminal del operador; en esta actualización no
se repitió la migración ni se consultó o escribió el backend remoto.

## Demostración de sustentación

Con Floci disponible, mostrar separación de workspace y state:

```bash
terraform -chdir=infra/terraform/local-floci workspace list
for env in dev test prod; do
  terraform -chdir=infra/terraform/local-floci workspace select "$env"
  terraform -chdir=infra/terraform/local-floci state pull | python3 -c 'import json,sys; s=json.load(sys.stdin); print("lineage",s["lineage"],"serial",s["serial"],"resources",len(s["resources"]))'
  terraform -chdir=infra/terraform/local-floci plan -input=false -lock-timeout=30s -var-file=infra/terraform/local-floci/floci.tfvars
done
```

Mostrar el historial versionado de cada objeto:

```bash
for env in dev test prod; do
  aws --endpoint-url http://127.0.0.1:4567 s3api list-object-versions \
    --bucket aegisvolt-floci-terraform-state --prefix "env/$env/terraform.tfstate"
done
```

El bootstrap permanece en `infra/terraform/local-floci-bootstrap` con su
backend local. No ejecutar `terraform init -reconfigure` en la raíz de
ambientes; el script operativo `scripts/floci-terraform.sh` exige que el
archivo backend local activo coincida con el ejemplo aprobado.

## Recuperación segura de versión S3

1. Detener operaciones Terraform concurrentes y listar versiones del objeto.
2. Elegir y registrar un `VersionId`; no borrar ni sobrescribir versiones.
3. Descargar esa versión a un archivo temporal y verificar que es JSON válido,
   que su lineage coincide con el workspace esperado y que serial/recursos son
   razonables frente al backup local con SHA-256.
4. Inspeccionar el plan contra el state descargado en un directorio de trabajo
   aislado. No ejecutar `state push` ni `put-object` en la demostración.
5. Una restauración real requiere autorización aparte: preservar el state
   actual con backup/versionado y hacer un `state push` deliberado solo después
   de revisar lineage y serial. No se restauró ningún state en esta tarea.

Ejemplo de descarga no destructiva (sustituir `VERSION_ID` obtenido en el paso 1):

```bash
aws --endpoint-url http://127.0.0.1:4567 s3api get-object \
  --bucket aegisvolt-floci-terraform-state \
  --key env/dev/terraform.tfstate --version-id VERSION_ID /tmp/dev-state-candidate.json
sha256sum /tmp/dev-state-candidate.json
python3 -m json.tool /tmp/dev-state-candidate.json >/dev/null
```

No apuntar el comando de descarga a `terraform.tfstate` local activo.

## Evidencia de bloqueo

Listar versiones por workspace:

```bash
aws --endpoint-url http://127.0.0.1:4567 s3api list-object-versions \
  --bucket aegisvolt-floci-terraform-state --prefix env/dev/terraform.tfstate
```

Repetir para `env/test/terraform.tfstate` y `env/prod/terraform.tfstate`.
Cada escritura del objeto bajo versionado debe crear una versión distinta.
La migración no se considera demostrada hasta ver versiones y comparar los
lineages obtenidos con `terraform state pull`.

El lock se demostró en el proyecto S3 descartable, no bloqueando un workspace
de entrega. Los archivos `.tflock` se limpian al completar normalmente.

La raíz de bootstrap declara política `DenyInsecureTransport`, pero la
observación reportada fue `NoSuchBucketPolicy` en Floci. Esto puede ser
limitación/no persistencia de la emulación o drift del recurso; no se cambia
la política ni se extrapola a AWS. El backend usa HTTP local y por eso su
compatibilidad se debe demostrar contra Floci, sin debilitar la configuración
de producción.

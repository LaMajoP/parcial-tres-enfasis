# CI/CD local de Floci

## Workflows

- `floci-plan.yml`: PR hacia `dev`, `test` o `prod`; resuelve el workspace con
  `github.base_ref`, ejecuta plan only y publica resumen en el job summary.
- `floci-apply.yml`: push posterior al merge a una de esas ramas; resuelve el
  ambiente con `github.ref_name` y ejecuta plan, guard de destrucción y apply
  solo en ese workspace. No despliega Kubernetes.
- El CI existente sigue haciendo lint, build, GraphQL, unit, integración y E2E
  en GitHub-hosted runners. Los workflows AWS existentes no se cambian ni se
  habilitan; sus gates `TF_PLAN_ENABLED` y `CD_ENABLED` siguen apagados.

El plan Floci se ejecuta solo en PR del mismo repositorio, de autores
OWNER/MEMBER/COLLABORATOR, no draft, con aprobación del Environment
`floci-plan-{dev,test,prod}`. No se ejecuta código de forks en el runner. El
Environment debe tener reviewers configurados antes de registrar el check
como requerido. El autor del PR no debe aprobar su propio Environment.

## Runner local seguro (no registrado)

Preparación recomendada, pendiente de autorización:

1. Host dedicado y actualizado, cuenta de sistema sin sudo y sin acceso al
   grupo `docker`; no montar `/var/run/docker.sock`.
2. Runner GitHub Actions instalado directamente en ese host, etiquetado
   `self-hosted`, `linux`, `aegisvolt-floci`; no usar etiquetas genéricas que
   los workflows AWS puedan seleccionar.
3. Floci debe seguir escuchando solo en loopback `127.0.0.1:4567`. No abrir
   puertos del router/firewall ni publicar Floci en internet.
4. Permitir al runner conexiones salientes HTTPS a GitHub para polling y
   descargar acciones; no crear listener entrante. Limitar egress adicional
   según las acciones aprobadas.
5. Instalar Terraform compatible con el lockfile, Python 3, AWS CLI y
   utilidades del repo. No instalar Docker en este runner; las pruebas Docker
   existentes continúan en runners hosted.
6. Recomendado: runner efímero/VM descartable para cada job, sin cachear
   `.terraform` ni conservar workspaces de checkout. En runner persistente,
   aislar usuario/directorio y limpiar el workspace después de cada ejecución.
7. No guardar credenciales AWS. El backend usa credenciales ficticias `floci`
   y endpoint loopback; `floci-ci-terraform.sh` aborta si detecta variables o
   perfiles de AWS.
8. Crear Environments `floci-plan-dev/test/prod` y `floci-dev/test/prod`, con
   reviewers. Para producción exigir aprobación explícita.

Instalación cuando se autorice: desde Settings → Actions → Runners → New
self-hosted runner, seleccionar Linux y seguir las instrucciones de descarga
y checksum que GitHub presente para la versión vigente. Registrar con labels
exclusivos, por ejemplo `aegisvolt-floci,linux` y `--no-default-labels`,
usando un token de registro temporal que no se guarde en logs ni en Git.
Instalarlo como servicio de la cuenta dedicada solo después de validar el
host; no ejecutar `config.sh` ni `svc.sh` como parte de esta implementación.

Riesgo residual: el runner puede leer todos los states del bucket local al
que accede el backend. La aprobación del Environment y la restricción a PR
internos reducen la exposición, pero no convierten el código revisado en
aislamiento técnico. No habilitar el plan self-hosted para PRs externos. No
registrar el runner hasta acordar host, mantenimiento, acceso al repo y
reviewers.

Como apply se activa con `push`, las protecciones remotas contra push directo
deben estar activas antes de registrar o poner online el runner. GitHub no se
consultó ni se modificó en esta tarea.

## Gobernanza de ramas

La política implementada en `ci.yml` es `feature/* → dev`, `dev → test`,
`test → prod`. `github-rulesets.sh` propone prohibición de deletion y
non-fast-forward, PR obligatorio, review y los checks existentes de CI.
Permanece en modo de solo lectura hasta una acción administrativa aprobada.

El contexto remoto exacto del nuevo check Floci aún no existe porque no se ha
registrado runner ni ejecutado workflow en GitHub. Por eso no se añade al
payload de required checks todavía. Tras un run real exitoso en PR, incorporar
el contexto exacto mostrado por GitHub al ruleset usando
`FLOCI_PLAN_REQUIRED_CONTEXT='<contexto observado>' bash scripts/github-rulesets.sh owner/repo`
y revisar el payload antes de una acción administrativa autorizada. No
adivinar el contexto. Comprobar el comportamiento de PR externos (skip) antes
de activar obligatoriedad. Los checks CI actuales siguen siendo obligatorios.

## Verificación local simulada

```bash
python3 -m unittest tests.scripts.test_floci_cicd -v
bash -n scripts/floci-environment.sh scripts/floci-ci-terraform.sh
python3 -m unittest tests.scripts.test_floci_cicd tests.scripts.test_floci_state_migrate -v
```

Estas pruebas simulan Terraform y validan selección/guardas. No son ejecución
en GitHub Actions ni acceso real a Floci. Para un primer run real se requiere
registrar el runner y configurar Environments/reviewers; esas acciones no se
realizaron.

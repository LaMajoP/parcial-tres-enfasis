# ADR-0003 — Workspaces con VPC por ambiente

**Decisión:** usar workspaces `dev`, `test`, `prod`, un state remoto versionado por workspace y VPC/CIDR dedicado por workspace.

**Consecuencia:** namespace no se usa como sustituto de VPC. `default` falla por check. El backend no intenta interpolar `terraform.workspace`; `workspace_key_prefix=env` genera claves como `env:/dev/aegisvolt.tfstate`.

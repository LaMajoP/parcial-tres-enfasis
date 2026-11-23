import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts/floci-state-migrate.sh"
BACKEND = REPO / "infra/terraform/local-floci/backend.s3.tf.example"


class MigrationHarness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.repo = self.base / "repo"
        self.root = self.repo / "infra/terraform/local-floci"
        (self.repo / "scripts").mkdir(parents=True)
        (self.root / "terraform.tfstate.d").mkdir(parents=True)
        (self.root / "backend.s3.tf.example").write_bytes(BACKEND.read_bytes())
        (self.repo / "scripts/floci-state-migrate.sh").write_bytes(SCRIPT.read_bytes())
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.remote = self.base / "remote"
        self.remote.mkdir()
        for i, env in enumerate(("dev", "test", "prod"), 1):
            state = {"version": 4, "lineage": f"lineage-{env}", "serial": i + 10,
                     "resources": [{"type": "aws_test", "name": env, "instances": []}]}
            path = self.root / "terraform.tfstate.d" / env / "terraform.tfstate"
            path.parent.mkdir()
            path.write_text(json.dumps(state))

        self._write("curl", "#!/bin/sh\nexit 0\n")
        self._write("aws", r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if os.getenv("MOCK_AWS_FAIL"): sys.exit(2)
if "s3api" in args: args = args[args.index("s3api"):]
if args[:2] == ["s3api", "head-bucket"]: sys.exit(0)
if args[:2] == ["s3api", "get-bucket-versioning"]: print("Enabled"); sys.exit(0)
if args[:2] == ["s3api", "list-object-versions"]:
    prefix = args[args.index("--prefix") + 1]
    keys = []
    for base, _, names in os.walk(os.environ["MOCK_REMOTE"]):
        for name in names:
            key = os.path.relpath(os.path.join(base, name), os.environ["MOCK_REMOTE"])
            if key == prefix: keys.append(key)
    print(json.dumps({"Versions": [{"Key": k} for k in keys], "DeleteMarkers": []}))
    sys.exit(0)
sys.exit(9)
''')
        self._write("terraform", r'''#!/usr/bin/env python3
import json, os, shutil, sys
a = sys.argv[1:]
if a and a[0].startswith("-chdir="): a = a[1:]
if "init" in a:
    with open(os.environ["MOCK_CALL_LOG"], "a") as log: log.write("init\n")
    if os.getenv("MOCK_TF_INIT_FAIL"): sys.exit(1)
    root = os.environ["MOCK_ROOT"]
    remote = os.environ["MOCK_REMOTE"]
    for env in ("dev", "test", "prod"):
        p = f"{root}/terraform.tfstate.d/{env}/terraform.tfstate"
        target = f"{remote}/env/{env}/terraform.tfstate"
        os.makedirs(os.path.dirname(target), exist_ok=True)
        state = json.load(open(p))
        state["serial"] += int(os.getenv("MOCK_SERIAL_DELTA", "1"))
        json.dump(state, open(target, "w"))
    sys.exit(0)
if a[0] == "workspace" and a[1] == "select":
    with open(os.environ["MOCK_CALL_LOG"], "a") as log: log.write(f"workspace {a[2]}\n")
    open(os.environ["MOCK_SELECTED_FILE"], "w").write(a[2])
    sys.exit(0)
if a[:2] == ["state", "pull"]:
    with open(os.environ["MOCK_CALL_LOG"], "a") as log: log.write("pull\n")
    env = open(os.environ["MOCK_SELECTED_FILE"]).read()
    sys.stdout.write(open(f"{os.environ['MOCK_REMOTE']}/env/{env}/terraform.tfstate").read())
    sys.exit(0)
sys.exit(0)
''')
        (self.repo / "scripts/floci-state-backup.sh").write_text(
            "#!/bin/sh\necho 'Respaldo inmutable creado: " + str(self.base / "backup") + " (3 archivos)'\n")
        (self.repo / "scripts/floci-state-backup.sh").chmod(0o755)
        backup = self.base / "backup/repository/infra/terraform/local-floci/terraform.tfstate.d"
        for env in ("dev", "test", "prod"):
            source = self.root / "terraform.tfstate.d" / env / "terraform.tfstate"
            target = backup / env / "terraform.tfstate"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        (self.base / "backup").mkdir(exist_ok=True)
        lines = []
        for env in ("dev", "test", "prod"):
            p = backup / env / "terraform.tfstate"
            import hashlib
            lines.append(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(self.base / 'backup')}")
        (self.base / "backup/SHA256SUMS").write_text("\n".join(lines) + "\n")
        for tool in self.bin.iterdir(): tool.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, name, content):
        (self.bin / name).write_text(content)

    def run_script(self, mode, **extra):
        env = os.environ.copy()
        env.update({"PATH": f"{self.bin}:{env['PATH']}", "MOCK_ROOT": str(self.root),
                    "MOCK_REMOTE": str(self.remote), "MOCK_SELECTED_FILE": str(self.base / "selected"),
                    "MOCK_CALL_LOG": str(self.base / "terraform.log")})
        env.update(extra)
        return subprocess.run(["bash", str(self.repo / "scripts/floci-state-migrate.sh"), mode],
                              cwd=self.repo, env=env, text=True, capture_output=True)

    def test_preflight_reads_without_staging_backend_or_remote_writes(self):
        result = self.run_script("preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PREFLIGHT OK", result.stdout)
        self.assertFalse((self.root / "backend.floci.s3.tf").exists())
        self.assertEqual(list(self.remote.iterdir()), [])

    def test_existing_remote_state_is_rejected(self):
        (self.remote / "env/dev/terraform.tfstate").parent.mkdir(parents=True)
        (self.remote / "env/dev/terraform.tfstate").touch()
        result = self.run_script("preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Destino remoto/versiones ya existen", result.stderr)

    def test_auth_or_endpoint_errors_are_not_treated_as_empty(self):
        result = self.run_script("preflight", MOCK_AWS_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PREFLIGHT OK", result.stdout)

    def test_partial_migration_is_not_automatically_reconfigured_or_retried(self):
        result = self.run_script("migrate", CONFIRM_FLOCI_STATE_MIGRATION="I_UNDERSTAND",
                                 MOCK_TF_INIT_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "backend.floci.s3.tf").exists(), result.stdout + result.stderr)
        retry = self.run_script("migrate", CONFIRM_FLOCI_STATE_MIGRATION="I_UNDERSTAND")
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn("No se reconfigura ni reintenta automáticamente", retry.stderr)

    def test_init_migration_is_followed_by_independent_checks_of_all_workspaces(self):
        result = self.run_script("migrate", CONFIRM_FLOCI_STATE_MIGRATION="I_UNDERSTAND")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for env in ("dev", "test", "prod"):
            self.assertIn(f"VERIFIED {env}: lineage=lineage-{env}", result.stdout)
        calls = (self.base / "terraform.log").read_text().splitlines()
        self.assertEqual(calls.count("init"), 1)
        self.assertEqual(calls.count("pull"), 3)
        self.assertEqual([x for x in calls if x.startswith("workspace ")],
                         ["workspace dev", "workspace test", "workspace prod"])

    def test_unjustified_serial_increment_is_rejected(self):
        result = self.run_script("migrate", CONFIRM_FLOCI_STATE_MIGRATION="I_UNDERSTAND",
                                 MOCK_SERIAL_DELTA="2")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Serial remoto fuera del rango esperado", result.stderr)

    def test_backend_config_is_local_and_workspace_paths_are_distinct(self):
        text = BACKEND.read_text()
        self.assertIn('s3 = "http://127.0.0.1:4567"', text)
        self.assertIn('workspace_key_prefix = "env"', text)
        self.assertIn('use_lockfile                = true', text)
        self.assertNotIn("amazonaws.com", text)
        self.assertEqual({f"env/{e}/terraform.tfstate" for e in ("dev", "test", "prod")},
                         {f"env/{e}/terraform.tfstate" for e in ("dev", "test", "prod")})


if __name__ == "__main__":
    unittest.main()

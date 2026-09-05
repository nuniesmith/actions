"""Exercise composite shell steps without a tailnet, SSH server, or Docker."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml


ACTIONS = Path(__file__).resolve().parents[1] / ".github/actions"
FAKE_TOOL = r'''#!/usr/bin/python3
import os
from pathlib import Path
import sys

root = Path(os.environ["COMPOSITE_TEST_ROOT"])
name = Path(sys.argv[0]).name
if name == "ssh":
    with (root / "ssh-calls").open("a") as calls:
        calls.write("call\n")
    sys.stdin.read()
    sys.exit(int(os.environ.get("SSH_EXIT_CODE", "0")))
if name == "tailscale":
    if sys.argv[1:] == ["logout"]:
        (root / "connected").unlink(missing_ok=True)
    elif not (root / "connected").exists():
        sys.exit(1)
    elif sys.argv[1:] == ["ip", "-4"]:
        print("100.64.0.1")
sys.exit(0)
'''


class DeployCompositeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="composite-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("ssh", "tailscale", "sleep"):
            target = self.bin / name
            target.write_text(FAKE_TOOL)
            target.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")
                    and not key.startswith("BASH_FUNC_")}
        self.env.update(PATH=str(self.bin), COMPOSITE_TEST_ROOT=str(self.root),
                        GITHUB_OUTPUT=str(self.root / "outputs"))

    def load(self, name):
        return yaml.safe_load((ACTIONS / name / "action.yml").read_text())

    def run_step(self, program, environment):
        return subprocess.run([shutil.which("bash"), "-e", "-o", "pipefail", "-c", program],
                              cwd=self.root, env={**self.env, **environment},
                              capture_output=True, text=True, timeout=10)

    def deploy(self, retries, status):
        action = self.load("ssh-deploy")
        step = next(step for step in action["runs"]["steps"] if step.get("id") == "deploy")
        environment = {}
        for name, expression in step["env"].items():
            match = re.fullmatch(r"\$\{\{ inputs\.([\w-]+) \}\}", expression)
            environment[name] = str(action["inputs"][match[1]].get("default", "")) if match else "key"
        environment.update(COMMAND_RETRIES=retries, SSH_EXIT_CODE=status,
                           PROJECT_PATH="lifeos", DEPLOY_COMMAND="run-migrations",
                           GIT_PULL="false", DOCKER_PRUNE="false")
        return self.run_step(step["run"], environment)

    def test_tailscale_remains_connected_after_composite(self):
        # Model the upstream action's successful connection, then run every
        # inline composite step: an early logout must break this assertion.
        (self.root / "connected").touch()
        for step in self.load("tailscale-connect")["runs"]["steps"]:
            if "run" in step:
                result = self.run_step(step["run"], {"TARGET_IP": "", "TARGET_SSH_PORT": "22", "WAIT_TIME": "0"})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / "connected").exists())
        self.assertIn("connected=true", (self.root / "outputs").read_text())

    def test_failed_migration_is_not_retried_when_disabled(self):
        result = self.deploy("1", "17")
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertEqual((self.root / "ssh-calls").read_text().splitlines(), ["call"])
        self.assertFalse((self.root / "outputs").exists())

    def test_default_command_attempts_are_retained(self):
        default = self.load("ssh-deploy")["inputs"]["command-retries"]["default"]
        result = self.deploy(default, "17")
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertEqual(len((self.root / "ssh-calls").read_text().splitlines()), 2)

    def test_invalid_attempts_fail_before_ssh(self):
        for retries in ("0", "-1", "false", "1; echo unsafe"):
            with self.subTest(retries=retries):
                result = self.deploy(retries, "0")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertFalse((self.root / "ssh-calls").exists())

    def test_custom_deployment_reports_success(self):
        result = self.deploy("1", "0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        outputs = (self.root / "outputs").read_text()
        self.assertIn("deployed=true", outputs)
        self.assertIn("build_strategy=custom", outputs)


if __name__ == "__main__":
    unittest.main()

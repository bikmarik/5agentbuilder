#!/usr/bin/env python3
"""Integration tests with protocol-compatible client fixtures; no paid model calls."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("models", REPO / "scripts/models.py")
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)

MOCK = '''
import json, os, sys
from pathlib import Path
client = Path(sys.argv[0]).name
catalog = json.loads(Path(os.environ["TEST_MODEL_CATALOG"]).read_text())
for line in sys.stdin:
    message = json.loads(line)
    if client == "codex":
        method = message["method"]
        if method == "initialized":
            continue
        if method == "initialize":
            result = {}
        elif method == "model/list":
            # Exercise multiple pages and ensure the cursor is passed through.
            second = message["params"].get("cursor") == "second"
            result = {"data": catalog[1:] if second else catalog[:1],
                      "nextCursor": None if second else "second"}
        else:
            sys.exit("Unexpected RPC: " + method)
        print(json.dumps({"id": message["id"], "result": result}), flush=True)
    else:
        assert message["type"] == "control_request"
        assert message["request"]["subtype"] == "initialize"
        print(json.dumps({"type": "control_response", "response": {
            "subtype": "success", "request_id": message["request_id"],
            "response": {"models": catalog}}}), flush=True)
'''


class ModelInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="five-agent-model-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "clone with spaces"
        shutil.copytree(REPO, self.repo, ignore=shutil.ignore_patterns(".git", "__pycache__"), symlinks=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("codex", "claude"):
            executable = self.bin / name
            executable.write_text("#!" + sys.executable + "\n" + MOCK)
            executable.chmod(0o755)
        self.catalog = self.root / "catalog.json"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        TEST_MODEL_CATALOG=str(self.catalog))

    def setup_client(self, target, shared=False):
        self.target = target
        self.home = self.root / (target + " home")
        self.home.mkdir()
        self.options = ["--target", target, "--" + target + "-home", str(self.home),
                        "--skills-dir", str(self.root / "skills")]
        self.extension = ".toml" if target == "codex" else ".md"
        self.config = self.home / ("config.toml" if target == "codex" else "settings.json")
        self.original = ('# Keep this comment\nmodel = "old-main"\n[other]\nmodel = "nested"\n'
                         if target == "codex" else '{"model":"old-main","permissions":{"allow":["Read"]}}\n')
        self.config.write_text(self.original)
        if shared:
            (self.home / "agents").mkdir()
            (self.home / "agents/unrelated.md").write_text("keep me\n")
        self.set_catalog("new-fast", "new-strong")

    def set_catalog(self, *names):
        if self.target == "codex":
            entries = [{"model": name, "displayName": name.upper(), "defaultReasoningEffort": "low"}
                       for name in names]
        else:
            entries = [{"value": name, "displayName": name.upper()} for name in names]
        self.catalog.write_text(json.dumps(entries))

    def run_script(self, script="install.sh", extra=(), answers="", success=True):
        result = subprocess.run(["bash", str(self.repo / script), *self.options, *extra],
                                input=answers, text=True, capture_output=True, env=self.env, timeout=20)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def assert_models(self, expected):
        for role, name in zip(models.ROLES, expected):
            if role == "chief":
                parsed = tomllib.loads(self.config.read_text()) if self.target == "codex" else json.loads(self.config.read_text())
                self.assertEqual(parsed["model"], name)
                if self.target == "codex":
                    self.assertEqual(parsed["model_reasoning_effort"], "low")
            else:
                text = (self.home / "agents" / (role + self.extension)).read_text()
                if self.target == "codex":
                    parsed = tomllib.loads(text)
                    self.assertEqual(parsed["model"], name)
                    self.assertEqual(parsed["model_reasoning_effort"], "low")
                else:
                    self.assertIn('model: ' + json.dumps(name) + '\n', text.split('---', 2)[1])

    def exercise_lifecycle(self, target, shared=False):
        self.setup_client(target, shared)
        templates = self.repo / ("agents" if target == "codex" else "claude/agents")
        originals = {p.name: p.read_bytes() for p in templates.iterdir()}
        result = self.run_script(answers="2\n1\n2\n2\n1\n")
        self.assertIn("automatic smoke test passed", result.stdout)
        for role in models.ROLES:
            self.assertIn(role.upper() + " (", result.stdout)
        self.assert_models(["new-strong", "new-fast", "new-strong", "new-strong", "new-fast"])
        self.assertEqual({p.name: p.read_bytes() for p in templates.iterdir()}, originals)
        self.assertEqual((self.home / ".five-agent-build/original-config").read_text(), self.original)
        if shared:
            self.assertEqual((self.home / "agents/unrelated.md").read_text(), "keep me\n")
        else:
            self.assertTrue((self.home / "agents").is_symlink())
            self.assertFalse((self.home / ("agents/scout" + self.extension)).is_symlink())
        # A changed live catalog is immediately reflected, including on --models.
        self.set_catalog("future-model")
        result = self.run_script(extra=["--models"], answers="1\n1\n1\n1\n1\n")
        self.assertIn("FUTURE-MODEL", result.stdout)
        self.assert_models(["future-model"] * 5)
        # Normal reinstall prompts too; Enter keeps every current choice.
        result = self.run_script(answers="\n" * 5)
        self.assertIn("[future-model]", result.stdout)
        self.assert_models(["future-model"] * 5)
        # Updates regenerate the role instructions while retaining model choices.
        scout = templates / ("scout" + self.extension)
        scout.write_text(scout.read_text() + "\n# Updated template\n")
        self.run_script(extra=["--keep-models"])
        self.assertIn("# Updated template", (self.home / "agents" / scout.name).read_text())
        self.assert_models(["future-model"] * 5)
        config = self.config.read_text()
        if target == "codex":
            self.assertIn("# Keep this comment", config)
            self.assertEqual(tomllib.loads(config)["other"]["model"], "nested")
        else:
            self.assertEqual(json.loads(config)["permissions"], {"allow": ["Read"]})
        # Neither validation nor uninstall resets the user's global main model.
        self.run_script(script="scripts/smoke-test.sh")
        self.run_script(script="uninstall.sh")
        self.assertEqual(self.config.read_text(), config)
        self.assertTrue(scout.exists())
        self.run_script(extra=["--keep-models"])
        self.assert_models(["future-model"] * 5)

    def test_codex_lifecycle(self):
        self.exercise_lifecycle("codex")

    def test_claude_lifecycle(self):
        self.exercise_lifecycle("claude")

    def test_shared_agents(self):
        self.exercise_lifecycle("codex", shared=True)

    def test_shared_claude_agents(self):
        self.exercise_lifecycle("claude", shared=True)

    def test_existing_directory_symlink_migrates_without_editing_checkout(self):
        self.setup_client("codex")
        self.run_script(extra=["--keep-models"])
        original = (self.repo / "agents/scout.toml").read_text()
        self.run_script(answers="1\n" * 5)
        self.assert_models(["new-fast"] * 5)
        self.assertEqual((self.repo / "agents/scout.toml").read_text(), original)
        self.assertEqual(os.readlink(self.home / "agents"), str(self.home / ".five-agent-build/agents"))

    def test_symlinked_config_and_modified_shared_agent_are_preserved(self):
        self.setup_client("codex", shared=True)
        outside = self.root / "outside.toml"
        self.config.rename(outside)
        self.config.symlink_to(outside)
        self.run_script(answers="1\n" * 5, success=False)
        self.assertEqual(outside.read_text(), self.original)
        self.config.unlink()
        self.config.write_text(self.original)
        self.run_script(answers="1\n" * 5)
        scout = self.home / "agents/scout.toml"
        scout.write_text(scout.read_text() + "# manual edit\n")
        self.run_script(extra=["--models"], answers="2\n" * 5, success=False)
        self.assertIn("# manual edit", scout.read_text())

    def test_cancel_eof_empty_catalog_and_silent_dry_run(self):
        self.setup_client("codex")
        for answers in ("q\n", "2\n1\n", ""):
            self.run_script(answers=answers, success=False)
            self.assertEqual(self.config.read_text(), self.original)
            self.assertFalse((self.home / "agents").exists())
        self.set_catalog()
        self.run_script(answers="1\n" * 5, success=False)
        result = self.run_script(extra=["--dry-run"])
        self.assertEqual(result.stdout + result.stderr, "")
        self.assertFalse((self.home / "agents").exists())

    def test_invalid_input_recovers_and_global_settings_race_refused(self):
        self.setup_client("claude")
        result = self.run_script(answers="bad\n99\n2\n1\n2\n2\n1\n")
        self.assertIn("Choose 1", result.stdout)
        args = type("Args", (), {"target": self.target, "home": str(self.home), "repo": str(self.repo)})()
        installation = models.Installation(args)
        plan = {"models": installation.current(), "config_before": self.config.read_text()}
        self.config.write_text('{"model":"changed-elsewhere"}\n')
        with self.assertRaisesRegex(ValueError, "changed during selection"):
            installation.apply(plan)
        self.assertEqual(json.loads(self.config.read_text())["model"], "changed-elsewhere")

    def test_atomic_failure_restores_previous_installation(self):
        self.setup_client("codex")
        self.run_script(extra=["--keep-models"])
        args = type("Args", (), {"target": self.target, "home": str(self.home), "repo": str(self.repo)})()
        installation = models.Installation(args)
        plan = {"models": {role: {"id": "new-fast"} for role in models.ROLES},
                "config_before": self.config.read_text()}
        original_write = models.atomic_write

        def fail_config(path, text):
            if path == self.config:
                raise OSError("injected failure")
            original_write(path, text)

        with patch.object(models, "atomic_write", side_effect=fail_config):
            with self.assertRaisesRegex(OSError, "injected failure"):
                installation.apply(plan)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertEqual(os.readlink(self.home / "agents"), str(self.repo / "agents"))
        self.assertFalse((self.home / ".five-agent-build").exists())

    def test_toml_patch_preserves_nested_keys_and_strings(self):
        text = 'note = """\nmodel = \\"inside\\"\n"""\nmodel = "old" # comment\n[x]\nmodel = "nested"\n'
        changed = models.change_toml_model(text, "next")
        self.assertEqual(tomllib.loads(changed), dict(tomllib.loads(text), model="next"))


if __name__ == "__main__":
    unittest.main()

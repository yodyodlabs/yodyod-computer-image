import importlib.util
import os
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(os.environ.get("YODYOD_SOURCE_ROOT", str(Path(__file__).resolve().parents[1])))
spec = importlib.util.spec_from_file_location("bootstrap", ROOT / "runtime" / "bootstrap.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ)
        self.env.start()
        self.addCleanup(self.env.stop)
        os.environ.pop("CODEX_HOME", None)

    def seed(self):
        module.bootstrap(self.home, ROOT / "config")

    def test_fresh_volume_is_seeded_and_repeat_is_idempotent(self):
        self.seed()
        path = self.home / ".codex" / "config.toml"
        original = path.read_bytes()
        self.assertEqual(len(tomllib.loads(original.decode())["mcp_servers"]), 3)
        self.assertTrue((self.home / "workspace").is_dir())
        self.assertEqual(tomllib.loads(original.decode())["sandbox_mode"], "danger-full-access")
        self.assertEqual(tomllib.loads(original.decode())["approval_policy"], "never")
        self.seed()
        self.assertEqual(path.read_bytes(), original)

    def test_preserves_user_settings_and_existing_server(self):
        folder = self.home / ".codex"
        folder.mkdir()
        original = 'model = "user-model"\nsandbox_mode = "read-only"\napproval_policy = "on-request"\n[mcp_servers.yodyod_browser]\ncommand = "custom-browser"\n'
        (folder / "config.toml").write_text(original)
        (self.home / "AGENTS.md").write_text("My own instructions\n")
        self.seed()
        parsed = tomllib.loads((folder / "config.toml").read_text())
        self.assertEqual(parsed["model"], "user-model")
        self.assertEqual(parsed["sandbox_mode"], "read-only")
        self.assertEqual(parsed["approval_policy"], "on-request")
        self.assertEqual(parsed["mcp_servers"]["yodyod_browser"]["command"], "custom-browser")
        self.assertEqual((self.home / "AGENTS.md").read_text(), "My own instructions\n")

    def test_invalid_config_is_left_intact(self):
        folder = self.home / ".codex"
        folder.mkdir()
        path = folder / "config.toml"
        path.write_text("[broken")
        with self.assertRaises(tomllib.TOMLDecodeError):
            self.seed()
        self.assertEqual(path.read_text(), "[broken")


if __name__ == "__main__":
    unittest.main()

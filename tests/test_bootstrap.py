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
        self.assertIn('WebBrowser=yodyod-chrome', (self.home / '.config/xfce4/helpers.rc').read_text())
        self.assertIn('/usr/local/bin/yodyod-browser', (self.home / '.local/share/applications/yodyod-chrome.desktop').read_text())
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
        helpers = self.home / '.config/xfce4/helpers.rc'
        helpers.parent.mkdir(parents=True)
        helpers.write_text('TerminalEmulator=custom-terminal\nWebBrowser=firefox\n')
        self.seed()
        parsed = tomllib.loads((folder / "config.toml").read_text())
        self.assertEqual(parsed["model"], "user-model")
        self.assertEqual(parsed["sandbox_mode"], "read-only")
        self.assertEqual(parsed["approval_policy"], "on-request")
        self.assertEqual(parsed["mcp_servers"]["yodyod_browser"]["command"], "custom-browser")
        self.assertEqual((self.home / "AGENTS.md").read_text(), "My own instructions\n")
        self.assertIn('TerminalEmulator=custom-terminal', helpers.read_text())
        self.assertNotIn('WebBrowser=firefox', helpers.read_text())

    def test_removes_legacy_firefox_shortcut_and_preserves_user_files(self):
        desktop = self.home / "Desktop"
        desktop.mkdir()
        (desktop / "firefox.desktop").write_text("[Desktop Entry]\nExec=firefox\n")
        (desktop / "notes.txt").write_text("User notes\n")
        profile = self.home / ".mozilla/firefox"
        profile.mkdir(parents=True)
        (profile / "profiles.ini").write_text("Existing profile\n")
        self.seed()
        self.assertFalse((desktop / "firefox.desktop").exists())
        self.assertTrue((desktop / "yodyod-chrome.desktop").is_file())
        self.assertEqual((desktop / "notes.txt").read_text(), "User notes\n")
        self.assertEqual((profile / "profiles.ini").read_text(), "Existing profile\n")
        self.seed()

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

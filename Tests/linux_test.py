import importlib.util
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).parents[1] / "linux" / "codex_meter_features.py"
SPEC = importlib.util.spec_from_file_location("codex_meter_features_test", MODULE_PATH)
features = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(features)


class LinuxProviderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.original_paths = (
            features.CONFIG_DIR,
            features.ACCOUNTS_DIR,
            features.CONFIG_FILE,
            features.LIVE_CODEX_HOME,
        )
        features.CONFIG_DIR = root / "config"
        features.ACCOUNTS_DIR = features.CONFIG_DIR / "accounts"
        features.CONFIG_FILE = features.CONFIG_DIR / "accounts.json"
        features.LIVE_CODEX_HOME = root / "live"
        features.LIVE_CODEX_HOME.mkdir()

    def tearDown(self):
        (
            features.CONFIG_DIR,
            features.ACCOUNTS_DIR,
            features.CONFIG_FILE,
            features.LIVE_CODEX_HOME,
        ) = self.original_paths
        self.temporary.cleanup()

    def test_imports_current_account_and_switches_atomically(self):
        live_auth = features.LIVE_CODEX_HOME / "auth.json"
        live_auth.write_text("first")
        store = features.AccountStore()

        self.assertEqual(len(store.profiles), 1)
        stored_auth = Path(store.profiles[0]["codexHome"]) / "auth.json"
        self.assertEqual(stored_auth.read_text(), "first")
        self.assertEqual(stored_auth.stat().st_mode & 0o777, 0o600)

        second_home = features.ACCOUNTS_DIR / "second"
        second_home.mkdir(parents=True)
        (second_home / "auth.json").write_text("second")
        second = store.add({"account": {"email": "second@example.com"}}, second_home)
        live_auth.write_text("first-updated")
        store.switch(second)

        self.assertEqual(live_auth.read_text(), "second")
        self.assertEqual(stored_auth.read_text(), "first-updated")
        self.assertEqual(live_auth.stat().st_mode & 0o777, 0o600)
        self.assertEqual(store.active_id, "second")

    def test_decodes_cursor_identity(self):
        import base64

        payload = base64.urlsafe_b64encode(json.dumps({
            "sub": "auth0|user-123", "email": "dev@example.com", "exp": time.time() + 3600,
        }).encode()).decode().rstrip("=")
        user_id, email = features.decode_cursor_identity(f"header.{payload}.signature")
        self.assertEqual(user_id, "user-123")
        self.assertEqual(email, "dev@example.com")

    def test_display_helpers(self):
        self.assertEqual(features.remaining({"usedPercent": 27}), 73)
        self.assertEqual(features.compact(4_451_062_882), "4.5B")
        self.assertEqual(features.money(1250), "$12.50")

    def test_finds_codex_outside_desktop_path(self):
        executable = Path(self.temporary.name) / "bundled-codex"
        executable.touch(mode=0o755)
        with mock.patch.dict(features.os.environ, {}, clear=True), mock.patch.object(
            features.shutil, "which", return_value=None
        ), mock.patch.object(features, "CODEX_FALLBACK_PATHS", (executable,)):
            self.assertEqual(features.codex_executable(), str(executable))

if __name__ == "__main__":
    unittest.main()

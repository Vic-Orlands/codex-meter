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

    def test_removes_active_account_and_live_credentials(self):
        live_auth = features.LIVE_CODEX_HOME / "auth.json"
        live_auth.write_text("revoked")
        store = features.AccountStore()
        profile = store.profiles[0]
        profile_home = Path(profile["codexHome"])

        store.remove(profile)

        self.assertEqual(store.profiles, [])
        self.assertIsNone(store.active_id)
        self.assertFalse(live_auth.exists())
        self.assertFalse(profile_home.exists())
        reloaded = features.AccountStore()
        self.assertEqual(reloaded.profiles, [])

    def test_removes_inactive_account_without_signing_out(self):
        live_auth = features.LIVE_CODEX_HOME / "auth.json"
        live_auth.write_text("active")
        store = features.AccountStore()
        second_home = features.ACCOUNTS_DIR / "second"
        second_home.mkdir(parents=True)
        (second_home / "auth.json").write_text("inactive")
        second = store.add({"account": {"email": "second@example.com"}}, second_home)

        store.remove(second)

        self.assertEqual(len(store.profiles), 1)
        self.assertEqual(live_auth.read_text(), "active")
        self.assertFalse(second_home.exists())

    def test_shortens_revoked_token_error(self):
        error = "failed to fetch: 401 Unauthorized: token_revoked " + "x" * 1000
        self.assertEqual(
            features.codex_error_message(error),
            "This account’s sign-in has expired. Remove it, then add the account again.",
        )

    def test_restarts_codex_desktop_with_registered_launcher(self):
        process_result = mock.Mock(stdout="")
        with mock.patch.object(features.shutil, "which", return_value="/usr/bin/gtk-launch"), \
             mock.patch.object(features.subprocess, "run", return_value=process_result) as run, \
             mock.patch.object(features.subprocess, "Popen") as popen:
            features.restart_codex_desktop()

        run.assert_called_once_with(
            ["pgrep", "-x", "ChatGPT"], capture_output=True, text=True, check=False
        )
        popen.assert_called_once_with(
            ["/usr/bin/gtk-launch", "chatgpt"],
            stdout=features.subprocess.DEVNULL,
            stderr=features.subprocess.DEVNULL,
            start_new_session=True,
        )

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

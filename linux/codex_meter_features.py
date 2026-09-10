"""Linux account and Cursor providers for the Codex Meter desktop app."""

import base64
import json
import os
import select
import shutil
import signal
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta
from pathlib import Path


CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "codex-meter"
ACCOUNTS_DIR = CONFIG_DIR / "accounts"
CONFIG_FILE = CONFIG_DIR / "accounts.json"
LIVE_CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
CODEX_FALLBACK_PATHS = (
    Path("/usr/lib/chatgpt/resources/codex"),
    Path.home() / ".local/bin/codex",
    Path.home() / ".cargo/bin/codex",
    Path.home() / ".npm-global/bin/codex",
    Path.home() / ".bun/bin/codex",
)


class AppServer:
    def __init__(self, executable, codex_home, timeout=30):
        environment = os.environ.copy()
        environment["CODEX_HOME"] = str(codex_home)
        self.timeout = timeout
        self.next_id = 1
        Path(codex_home).mkdir(mode=0o700, parents=True, exist_ok=True)
        self.process = subprocess.Popen(
            [executable, "app-server", "--stdio"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
            env=environment,
        )

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)

    def send(self, payload):
        self.process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def read(self, deadline):
        while time.monotonic() < deadline:
            ready, _, _ = select.select(
                [self.process.stdout], [], [], max(0, deadline - time.monotonic())
            )
            if not ready:
                break
            line = self.process.stdout.readline()
            if line:
                return json.loads(line)
            error = self.process.stderr.read().strip()
            raise RuntimeError(error or "Codex app-server closed unexpectedly")
        raise RuntimeError("Codex app-server timed out")

    def request(self, method, params=None, optional=False):
        request_id = self.next_id
        self.next_id += 1
        self.send({"method": method, "id": request_id, "params": params or {}})
        deadline = time.monotonic() + self.timeout
        while True:
            message = self.read(deadline)
            if message.get("id") != request_id:
                continue
            if "error" in message:
                if optional:
                    return None
                error = message["error"]
                raise RuntimeError(
                    error.get("message", str(error)) if isinstance(error, dict) else str(error)
                )
            return message.get("result")

    def initialize(self):
        self.request("initialize", {
            "clientInfo": {
                "name": "codex-meter-linux", "title": "Codex Meter", "version": "0.2.0"
            },
            "capabilities": {"experimentalApi": True},
        })
        self.send({"method": "initialized", "params": {}})

    def wait_for_login(self, login_id):
        deadline = time.monotonic() + self.timeout
        while True:
            message = self.read(deadline)
            if message.get("method") != "account/login/completed":
                continue
            params = message.get("params") or {}
            if params.get("loginId") != login_id:
                continue
            if params.get("success") is False:
                raise RuntimeError(params.get("error") or "Codex login failed")
            return


def codex_executable():
    configured = os.environ.get("CODEX_METER_CODEX_PATH")
    if configured:
        return os.path.expanduser(configured)

    executable = shutil.which("codex")
    if executable:
        return executable

    # Desktop sessions commonly have a smaller PATH than interactive shells.
    # In particular, Codex Desktop bundles its CLI outside the standard PATH.
    for candidate in CODEX_FALLBACK_PATHS:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    raise RuntimeError(
        "Codex CLI was not found. Install Codex or set CODEX_METER_CODEX_PATH."
    )


def fetch_codex(codex_home):
    server = AppServer(codex_executable(), codex_home)
    try:
        server.initialize()
        account = server.request("account/read", {"refreshToken": False})
        limits = server.request("account/rateLimits/read")
        usage = server.request("account/usage/read", optional=True)
        return {
            "account": (account or {}).get("account") or {},
            "rateLimits": (limits or {}).get("rateLimits") or {},
            "usage": (usage or {}).get("summary") or {},
            "dailyUsage": (usage or {}).get("dailyUsageBuckets") or [],
        }
    finally:
        server.close()


def login_codex(codex_home, on_url):
    server = AppServer(codex_executable(), codex_home, timeout=300)
    try:
        server.initialize()
        response = server.request("account/login/start", {
            "type": "chatgpt", "codexStreamlinedLogin": True
        }) or {}
        url = response.get("authUrl") or response.get("verificationUrl")
        login_id = response.get("loginId")
        if not url or not login_id:
            raise RuntimeError("The Codex app-server returned an invalid login response")
        on_url(url)
        server.wait_for_login(login_id)
    finally:
        server.close()
    return fetch_codex(codex_home)


def atomic_copy(source, destination):
    source, destination = Path(source), Path(destination)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = destination.parent / f".auth-{uuid.uuid4()}.tmp"
    shutil.copyfile(source, temporary)
    temporary.chmod(0o600)
    os.replace(temporary, destination)
    destination.chmod(0o600)


class AccountStore:
    def __init__(self):
        self.profiles = []
        self.active_id = None
        self.load()
        if not self.profiles and (LIVE_CODEX_HOME / "auth.json").is_file():
            self.import_current()

    def load(self):
        try:
            payload = json.loads(CONFIG_FILE.read_text())
            self.profiles = payload.get("profiles") or []
            self.active_id = payload.get("activeID")
        except (OSError, ValueError):
            pass

    def save(self):
        CONFIG_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        temporary = CONFIG_FILE.with_suffix(".tmp")
        temporary.write_text(json.dumps({
            "profiles": self.profiles, "activeID": self.active_id
        }, indent=2))
        temporary.chmod(0o600)
        os.replace(temporary, CONFIG_FILE)

    def import_current(self):
        profile_id = str(uuid.uuid4())
        home = ACCOUNTS_DIR / profile_id
        atomic_copy(LIVE_CODEX_HOME / "auth.json", home / "auth.json")
        self.profiles.append({
            "id": profile_id, "name": "Current account", "codexHome": str(home)
        })
        self.active_id = profile_id
        self.save()

    def add(self, snapshot, home):
        account = snapshot.get("account") or {}
        profile = {
            "id": home.name,
            "name": account.get("email") or f"Account {len(self.profiles) + 1}",
            "codexHome": str(home),
        }
        self.profiles.append(profile)
        self.save()
        return profile

    def rename(self, profile, name):
        if name.strip():
            profile["name"] = name.strip()
            self.save()

    def remove(self, profile):
        if profile not in self.profiles:
            return

        was_active = profile["id"] == self.active_id
        self.profiles.remove(profile)
        if was_active:
            self.active_id = None
            live_auth = LIVE_CODEX_HOME / "auth.json"
            if live_auth.is_file():
                live_auth.unlink()

        home = Path(profile["codexHome"])
        try:
            is_managed_home = home.resolve().parent == ACCOUNTS_DIR.resolve()
        except OSError:
            is_managed_home = False
        if is_managed_home and home.exists():
            shutil.rmtree(home)
        self.save()

    def switch(self, profile):
        live_auth = LIVE_CODEX_HOME / "auth.json"
        current = self.by_id(self.active_id)
        if current and live_auth.is_file():
            atomic_copy(live_auth, Path(current["codexHome"]) / "auth.json")
        selected_auth = Path(profile["codexHome"]) / "auth.json"
        if not selected_auth.is_file():
            raise RuntimeError("No Codex auth.json was found for this account")
        atomic_copy(selected_auth, live_auth)
        self.active_id = profile["id"]
        self.save()

    def sync_active(self):
        current = self.by_id(self.active_id)
        live_auth = LIVE_CODEX_HOME / "auth.json"
        if not current or not live_auth.is_file():
            return
        destination = Path(current["codexHome"]) / "auth.json"
        if (
            not destination.exists()
            or live_auth.stat().st_mtime_ns != destination.stat().st_mtime_ns
            or live_auth.stat().st_size != destination.stat().st_size
        ):
            atomic_copy(live_auth, destination)

    def by_id(self, profile_id):
        return next((item for item in self.profiles if item["id"] == profile_id), None)


def codex_error_message(message):
    lowered = message.lower()
    if "token_revoked" in lowered or "invalidated oauth token" in lowered:
        return "This account’s sign-in has expired. Remove it, then add the account again."
    if "401 unauthorized" in lowered:
        return "This account is no longer authorized. Remove it, then add the account again."
    return message if len(message) <= 300 else message[:297] + "…"


def restart_codex_desktop(timeout=5):
    """Close the Linux ChatGPT/Codex desktop app and launch it again."""
    launcher = shutil.which("gtk-launch")
    if not launcher:
        raise RuntimeError(
            "The account was switched, but Codex could not be reopened automatically."
        )

    process_ids = subprocess.run(
        ["pgrep", "-x", "ChatGPT"], capture_output=True, text=True, check=False
    ).stdout.split()
    for process_id in process_ids:
        try:
            os.kill(int(process_id), signal.SIGTERM)
        except (ProcessLookupError, ValueError):
            pass

    deadline = time.monotonic() + timeout
    while process_ids and time.monotonic() < deadline:
        process_ids = [
            process_id for process_id in process_ids
            if Path(f"/proc/{process_id}").exists()
        ]
        if process_ids:
            time.sleep(0.1)
    if process_ids:
        raise RuntimeError(
            "The account was switched, but Codex did not close. Quit and reopen it to apply."
        )

    subprocess.Popen(
        [launcher, "chatgpt"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def cursor_database():
    candidates = [
        Path.home() / ".config/Cursor/User/globalStorage/state.vscdb",
        Path.home() / ".config/cursor/User/globalStorage/state.vscdb",
        Path.home() / "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
    ]
    return next((path for path in candidates if path.is_file()), None)


def cursor_token():
    database = cursor_database()
    if not database:
        raise RuntimeError("Cursor’s local account database was not found")
    try:
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=0.5) as connection:
            row = connection.execute(
                "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
                ("cursorAuth/accessToken",),
            ).fetchone()
    except sqlite3.Error as error:
        raise RuntimeError(f"Could not read Cursor’s local session: {error}") from error
    if not row or not row[0].strip():
        raise RuntimeError("Cursor is not signed in. Open Cursor and sign in first")
    return row[0].strip()


def decode_cursor_identity(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        user_id = claims["sub"].split("|")[-1]
        expires = float(claims["exp"])
    except (IndexError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeError("Cursor’s local session is invalid") from error
    if expires - time.time() <= 60:
        raise RuntimeError(
            "Cursor’s local session has expired. Open Cursor so it can refresh the session"
        )
    if not user_id or any(not (char.isalnum() or char in "._-") for char in user_id):
        raise RuntimeError("Cursor’s local session is invalid")
    return user_id, claims.get("email")


def cursor_request(path, cookie, data=None, timeout=20):
    body = json.dumps(data).encode() if data is not None else None
    headers = {"Accept": "application/json", "Cookie": cookie}
    if body is not None:
        headers.update({"Content-Type": "application/json", "Origin": "https://cursor.com"})
    request = urllib.request.Request("https://cursor.com" + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise RuntimeError(
                "Cursor’s local session has expired. Open Cursor so it can refresh the session"
            ) from error
        raise RuntimeError(f"Cursor usage request failed: HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Cursor usage request failed: {error.reason}") from error


def fetch_cursor(include_activity=True):
    token = cursor_token()
    user_id, token_email = decode_cursor_identity(token)
    cookie = f"WorkosCursorSessionToken={user_id}%3A%3A{token}"
    summary = cursor_request("/api/usage-summary", cookie)
    try:
        user = cursor_request("/api/auth/me", cookie)
    except RuntimeError:
        user = {}
    individual = summary.get("individualUsage") or {}
    team = summary.get("teamUsage") or {}
    plan = individual.get("plan") or individual.get("overall") or team.get("pooled") or {}
    used, limit = number(plan.get("used")), number(plan.get("limit"))
    percent = plan.get("totalPercentUsed")
    if percent is None:
        percent = used / limit * 100 if limit else 0
    activity = fetch_cursor_activity(cookie) if include_activity else {
        "totalTokens": 0, "dailyUsage": []
    }
    return {
        "email": user.get("email") or token_email,
        "membershipType": summary.get("membershipType"),
        "billingCycleEnd": summary.get("billingCycleEnd"),
        "planUsedCents": used,
        "planLimitCents": limit,
        "planPercentUsed": max(0, min(100, percent)),
        "autoPercentUsed": plan.get("autoPercentUsed"),
        "apiPercentUsed": plan.get("apiPercentUsed"),
        "onDemandUsedCents": number(
            (individual.get("onDemand") or team.get("onDemand") or {}).get("used")
        ),
        **activity,
    }


def fetch_cursor_activity(cookie):
    start = datetime.now().astimezone() - timedelta(days=111)
    events = []
    for page in range(1, 21):
        result = cursor_request(
            "/api/dashboard/get-filtered-usage-events", cookie,
            {
                "page": page, "pageSize": 1000,
                "startDate": str(int(start.timestamp() * 1000)),
                "endDate": str(int(time.time() * 1000)),
            }, timeout=30,
        )
        batch = result.get("usageEventsDisplay") or []
        events.extend(batch)
        if len(batch) < 1000:
            break
    daily, total = {}, 0
    for event in events:
        usage = event.get("tokenUsage") or {}
        tokens = sum(max(0, number(usage.get(key))) for key in (
            "inputTokens", "outputTokens", "cacheWriteTokens", "cacheReadTokens"
        ))
        timestamp = number(event.get("timestamp"))
        if tokens and timestamp:
            day = datetime.fromtimestamp(timestamp / 1000).strftime("%Y-%m-%d")
            daily[day] = daily.get(day, 0) + tokens
            total += tokens
    return {
        "totalTokens": total,
        "dailyUsage": [
            {"startDate": day, "tokens": daily[day]} for day in sorted(daily)
        ],
    }


def number(value):
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def remaining(window):
    return None if not window else max(0, min(100, 100 - number(window.get("usedPercent"))))


def money(cents):
    return f"${number(cents) / 100:,.2f}".replace(".00", "")


def compact(value):
    value = number(value)
    for divisor, suffix in ((1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")):
        if value >= divisor:
            return f"{value / divisor:.1f}".rstrip("0").rstrip(".") + suffix
    return str(value) if value else "—"


def reset_text(window):
    if not window or not window.get("resetsAt"):
        return "Reset unavailable"
    seconds = max(0, number(window["resetsAt"]) - int(time.time()))
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes = seconds // 60
    parts = ([f"{days}d"] if days else []) + ([f"{hours}h"] if hours else [])
    if minutes or not parts:
        parts.append(f"{minutes}m")
    return "Resets in " + " ".join(parts[:2])

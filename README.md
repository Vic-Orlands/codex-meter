# Codex Meter

Codex Meter keeps Codex and Cursor limits visible without handing credentials to an authentication library.

The native macOS 14+ menu-bar app shows 5-hour and weekly Codex windows, reset times, credits, account switching, Cursor plan usage, and a 16-week token activity view. A dependency-free command-line edition provides Codex usage on macOS and Linux.

## Install

### macOS menu-bar app

Clone and build the app locally:

```sh
git clone https://github.com/Vic-Orlands/codex-meter.git
cd codex-meter
Scripts/build-app.sh
open "dist/Codex Meter.app"
```

Requirements:

- macOS 14 or newer
- The official Codex CLI installed and signed in
- Cursor installed and signed in for Cursor usage

### Command line on macOS or Linux

The CLI requires Python 3.9+ and the official Codex CLI. It has no Python package dependencies.

```sh
git clone https://github.com/Vic-Orlands/codex-meter.git
cd codex-meter
Scripts/install-cli.sh
```

Ensure `~/.local/bin` is on `PATH`, then run:

```sh
codex-meter
codex-meter --watch 60
codex-meter --json
```

Use `--codex PATH` when Codex is not on `PATH`, or `--codex-home PATH` to inspect another Codex home.

## Privacy model

- No third-party runtime dependencies.
- OAuth, refresh-token handling, account details, rate limits, credits, and Codex usage come from the installed official `codex app-server` process.
- Each macOS app account has an isolated `CODEX_HOME` under `~/Library/Application Support/CodexMeter/Accounts`.
- Codex Meter never decodes or logs `auth.json`. Account switching uses an atomic local copy and enforces `0600` permissions.
- No analytics, telemetry, or remote database.

Cursor support opens Cursor's VS Code-style state database read-only and uses its existing short-lived access token only in memory with an ephemeral URL session. The token is never refreshed, printed, copied, or persisted. Cursor usage comes from Cursor's signed-in dashboard endpoints, which are not a documented public API and may need maintenance if Cursor changes them.

## Build locally

```sh
git clone https://github.com/Vic-Orlands/codex-meter.git
cd codex-meter
swift test
Scripts/build-app.sh
open "dist/Codex Meter.app"
```

Run the CLI tests with:

```sh
python3 -m unittest Tests/cli_test.py
```

## Platform scope

The tray interface uses SwiftUI and AppKit and is therefore macOS-only. The CLI runs on macOS and Linux and uses the same official app-server boundary without reading credentials. Cursor tracking is currently available only in the macOS app because it depends on Cursor's macOS local state.

## License

MIT

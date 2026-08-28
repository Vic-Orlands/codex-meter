# Codex Meter

Codex Meter keeps Codex and Cursor limits visible without handing credentials to an authentication library.

The native macOS 14+ menu-bar app shows 5-hour and weekly Codex windows, reset times, credits, account switching, Cursor plan usage, and a 16-week token activity view. A dependency-free command-line edition provides Codex usage on macOS and Linux.

## Install

### macOS menu-bar app

Download `CodexMeter-*-macOS.zip` from the [latest release](https://github.com/Vic-Orlands/codex-meter/releases/latest), extract it, and move **Codex Meter.app** to Applications.

Until the app is signed with a Developer ID and notarized, launch it the first time with Control-click → **Open**. Future releases become notarized automatically after the Apple signing secrets documented below are configured.

Requirements:

- macOS 14 or newer
- The official Codex CLI installed and signed in
- Cursor installed and signed in for Cursor usage

### Command line on macOS or Linux

The CLI requires Python 3.9+ and the official Codex CLI. It has no Python package dependencies.

```sh
curl -fsSL https://raw.githubusercontent.com/Vic-Orlands/codex-meter/main/Scripts/install-cli.sh | sh
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

## Releases and notarization

Pushing a `v*` tag runs the release workflow, tests both products, packages the macOS app and portable CLI, generates SHA-256 checksums, and publishes a GitHub release.

For trusted macOS distribution, add these GitHub Actions secrets:

- `APPLE_CERTIFICATE_BASE64`: Developer ID Application `.p12`, base64 encoded
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`
- `APPLE_SIGNING_IDENTITY`: full Developer ID Application identity
- `APPLE_ID`: Apple developer account email
- `APPLE_TEAM_ID`: Apple Developer team ID
- `APPLE_APP_PASSWORD`: app-specific password for notarization

Without those secrets, releases are ad-hoc signed and require the first-launch Control-click described above.

## Platform scope

The tray interface uses SwiftUI and AppKit and is therefore macOS-only. The CLI runs on macOS and Linux and uses the same official app-server boundary without reading credentials. Cursor tracking is currently available only in the macOS app because it depends on Cursor's macOS local state.

## License

MIT

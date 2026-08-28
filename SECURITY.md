# Security

Please report vulnerabilities privately through GitHub Security Advisories instead of opening a public issue.

Codex Meter does not accept, upload, or parse Codex `auth.json` credentials. The macOS app delegates Codex authentication and usage requests to the installed official `codex app-server`. Account switching copies the selected local credential file atomically and applies `0600` permissions.

Cursor support reads Cursor's local session database in read-only mode. Its short-lived session token remains in memory and is sent only to Cursor's own dashboard endpoints through an ephemeral URL session.

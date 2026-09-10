#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/dist/Codex Meter.app"
app_name="Codex Meter.app"

if [[ ! -d "$source_app" ]]; then
    echo "Missing $source_app — run Scripts/build-app.sh first." >&2
    exit 1
fi

if [[ -w /Applications ]]; then
    destination="/Applications/$app_name"
else
    mkdir -p "$HOME/Applications"
    destination="$HOME/Applications/$app_name"
fi

osascript -e 'tell application "Codex Meter" to quit' >/dev/null 2>&1 || true
if pgrep -x CodexMeter >/dev/null 2>&1; then
    pkill -x CodexMeter >/dev/null 2>&1 || true
    sleep 0.4
fi

rm -rf "$destination"
cp -R "$source_app" "$destination"
xattr -cr "$destination" >/dev/null 2>&1 || true

echo "$destination"

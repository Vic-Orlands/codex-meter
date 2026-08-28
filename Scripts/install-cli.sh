#!/bin/sh
set -eu

version="${CODEX_METER_VERSION:-main}"
install_dir="${CODEX_METER_INSTALL_DIR:-$HOME/.local/bin}"
source_url="https://raw.githubusercontent.com/Vic-Orlands/codex-meter/$version/cli/codex-meter"

mkdir -p "$install_dir"
destination="$install_dir/codex-meter"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$source_url" -o "$destination"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$destination" "$source_url"
else
    echo "curl or wget is required" >&2
    exit 1
fi

chmod 755 "$destination"
echo "Installed codex-meter to $destination"
case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) echo "Add $install_dir to your PATH." ;;
esac

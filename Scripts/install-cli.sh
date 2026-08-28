#!/bin/sh
set -eu

install_dir="${CODEX_METER_INSTALL_DIR:-$HOME/.local/bin}"
project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source_file="$project_dir/cli/codex-meter"

mkdir -p "$install_dir"
destination="$install_dir/codex-meter"

install -m 755 "$source_file" "$destination"
echo "Installed codex-meter to $destination"
case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) echo "Add $install_dir to your PATH." ;;
esac

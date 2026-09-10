#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
app_dir="$data_home/codex-meter"
desktop_dir="$data_home/applications"
icon_dir="$data_home/icons/hicolor/scalable/apps"
autostart=false

if [ "${1:-}" = "--autostart" ]; then
    autostart=true
elif [ -n "${1:-}" ]; then
    echo "Usage: $0 [--autostart]" >&2
    exit 2
fi

python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")' 2>/dev/null || {
    echo "Missing Ubuntu desktop libraries. Install gir1.2-gtk-3.0 and gir1.2-ayatanaappindicator3-0.1." >&2
    exit 1
}

mkdir -p "$app_dir" "$desktop_dir" "$icon_dir"
install -m 755 "$project_dir/linux/codex-meter" "$app_dir/codex-meter"
install -m 644 "$project_dir/linux/codex_meter_features.py" "$app_dir/codex_meter_features.py"
install -m 644 "$project_dir/linux/codex-meter.svg" "$icon_dir/codex-meter.svg"

desktop_file="$desktop_dir/io.github.vicorlands.CodexMeter.desktop"
sed "s|@EXEC@|$app_dir/codex-meter|g" "$project_dir/linux/io.github.vicorlands.CodexMeter.desktop.in" > "$desktop_file"
chmod 644 "$desktop_file"

if $autostart; then
    mkdir -p "$config_home/autostart"
    cp "$desktop_file" "$config_home/autostart/io.github.vicorlands.CodexMeter.desktop"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$data_home/icons/hicolor" >/dev/null 2>&1 || true

echo "Installed Codex Meter for Ubuntu."
echo "Run: $app_dir/codex-meter"

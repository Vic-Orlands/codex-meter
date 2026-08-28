#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release

app_dir="$project_dir/dist/Codex Meter.app"
contents_dir="$app_dir/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/.build/release/CodexMeter" "$contents_dir/MacOS/CodexMeter"
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"

icon_work_dir="$(mktemp -d)"
iconset_dir="$icon_work_dir/CodexMeter.iconset"
mkdir -p "$iconset_dir"
swift "$project_dir/Scripts/generate-icon.swift" "$icon_work_dir/icon.png"
for specification in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    pixels="${specification%% *}"
    filename="${specification#* }"
    sips -z "$pixels" "$pixels" "$icon_work_dir/icon.png" --out "$iconset_dir/$filename" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/CodexMeter.icns"
rm -R "$icon_work_dir"
codesign --force --deep --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$app_dir"
echo "$app_dir"

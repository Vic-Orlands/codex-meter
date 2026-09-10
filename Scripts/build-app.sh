#!/bin/zsh
set -euo pipefail

install_app=false
if [[ "${1:-}" == "--install" ]]; then
    install_app=true
fi

project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release

app_dir="$project_dir/dist/Codex Meter.app"
contents_dir="$app_dir/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
# Keep Launchpad/Spotlight from indexing the build artifact as a second app.
touch "$project_dir/dist/.metadata_never_index"
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

# Ad-hoc + hardened runtime is killed on Apple Silicon as
# "Code Signature Invalid" / Invalid Page. Keep hardened runtime
# only when signing with a real identity.
identity="${CODE_SIGN_IDENTITY:--}"
xattr -cr "$app_dir" >/dev/null 2>&1 || true
if [[ "$identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --sign "$identity" "$app_dir"
fi

# Dist is a build artifact, not a second install. Drop it from Launch Services
# so Launchpad does not keep a duplicate Codex Meter icon.
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$lsregister" ]]; then
    "$lsregister" -u "$app_dir" >/dev/null 2>&1 || true
fi
echo "$app_dir"

if $install_app; then
    "$project_dir/Scripts/install-app.sh"
fi

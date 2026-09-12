#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app=${1:-"$project_dir/.build/Q.app"}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
output_dir=${Q_RELEASE_DIR:-"$project_dir/Dist"}
output=${2:-"$output_dir/Q-$version.dmg"}
volume_name="Q Installer"
background="$project_dir/Resources/Installer/QInstallerBackground.png"

if [ ! -d "$app" ]; then
    echo "Missing packaged application at $app" >&2
    exit 1
fi
if [ ! -f "$background" ]; then
    echo "Missing installer background at $background" >&2
    exit 1
fi

mkdir -p "$output_dir"
staging_dir=$(mktemp -d /tmp/q-dmg-staging.XXXXXX)
mount_dir=
source_dir="$staging_dir/source"
read_write_dmg="$staging_dir/Q-read-write.dmg"
mounted=0
cleanup() {
    if [ "$mounted" -eq 1 ] && [ -n "$mount_dir" ]; then
        hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$source_dir/.background"
/usr/bin/ditto "$app" "$source_dir/Q.app"
/usr/bin/ditto "$background" "$source_dir/.background/QInstallerBackground.png"
ln -s /Applications "$source_dir/Applications"

rm -f "$output"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$source_dir" \
    -format UDRW \
    -ov \
    "$read_write_dmg" >/dev/null

attach_output=$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$read_write_dmg")
mount_dir=$(printf '%s\n' "$attach_output" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')
if [ -z "$mount_dir" ]; then
    echo "Could not locate the mounted Q disk image." >&2
    exit 1
fi
mounted=1

# Finder stores the background, icon positions, window size, and hidden chrome
# in the volume's .DS_Store. The actual Q and Applications icons remain normal,
# draggable Finder items laid over this visual instruction.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$volume_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {120, 100, 760, 602}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:QInstallerBackground.png"
        set position of item "Q.app" of container window to {320, 138}
        set position of item "Applications" of container window to {320, 368}
        update without registering applications
        delay 2
        close container window
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$mount_dir" >/dev/null
mounted=0

hdiutil convert "$read_write_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$output" >/dev/null

signing_identity=${Q_CODE_SIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application:/ { print $2; exit }')
fi
if [ -n "$signing_identity" ]; then
    codesign --force --timestamp --sign "$signing_identity" "$output"
fi

hdiutil verify "$output" >/dev/null
echo "$output"

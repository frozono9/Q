#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app=${1:-"$project_dir/.build/Q.app"}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
output_dir=${Q_RELEASE_DIR:-"$project_dir/Dist"}
output=${2:-"$output_dir/Q-$version.dmg"}
volume_name="Q Installer"

if [ ! -d "$app" ]; then
    echo "Missing packaged application at $app" >&2
    exit 1
fi

mkdir -p "$output_dir"
staging_dir=$(mktemp -d /tmp/q-dmg-staging.XXXXXX)
cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

/usr/bin/ditto "$app" "$staging_dir/Q.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$output"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$output" >/dev/null

signing_identity=${Q_CODE_SIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application:/ { print $2; exit }')
fi
if [ -n "$signing_identity" ]; then
    codesign --force --timestamp --sign "$signing_identity" "$output"
fi

hdiutil verify "$output" >/dev/null
echo "$output"

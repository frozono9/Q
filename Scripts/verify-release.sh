#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 path/to/Q.dmg" >&2
    exit 1
fi

dmg=$1
if [ ! -f "$dmg" ]; then
    echo "Missing disk image: $dmg" >&2
    exit 1
fi

mount_point=$(mktemp -d /tmp/q-release-verify.XXXXXX)
cleanup() {
    hdiutil detach "$mount_point" -quiet 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point" -quiet
app="$mount_point/Q.app"

test -d "$app"
test -L "$mount_point/Applications"
test -x "$app/Contents/MacOS/Q"
test -x "$app/Contents/MacOS/QDeviceWatcher"
test -x "$app/Contents/MacOS/QClaudeHook"
test -f "$app/Contents/Resources/Updater/Q-Firmware-0.2.3.bin"

for executable in Q QDeviceWatcher QClaudeHook; do
    architectures=$(lipo -archs "$app/Contents/MacOS/$executable")
    echo "$architectures" | grep -q arm64
    echo "$architectures" | grep -q x86_64
done

codesign --verify --deep --strict --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
sha=$(shasum -a 256 "$dmg" | awk '{print $1}')

echo "Verified Q $version"
echo "Firmware payload: 0.2.3"
echo "SHA-256: $sha"

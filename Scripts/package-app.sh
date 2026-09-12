#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
binary="$project_dir/.build/arm64-apple-macosx/$configuration/Q"
bundle="$project_dir/.build/Q.app"

if [ ! -x "$binary" ]; then
    echo "Missing Q executable at $binary. Build Q first." >&2
    exit 1
fi

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary" "$bundle/Contents/MacOS/Q"
cp "$project_dir/Config/Info.plist" "$bundle/Contents/Info.plist"
cp "$project_dir/Resources/Brand/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/Brand/QLogo.png" "$bundle/Contents/Resources/QLogo.png"
cp "$project_dir/Resources/Brand/QMenuBarTemplate.png" "$bundle/Contents/Resources/QMenuBarTemplate.png"
chmod +x "$bundle/Contents/MacOS/Q"

# Accessibility permissions are tied to the app's signing requirement. An
# ad-hoc signature uses the build's changing code hash, so macOS can display Q
# as enabled while rejecting the newly built process. Prefer a stable local
# signing identity when one is available; retain ad-hoc signing as a portable
# fallback for contributors without a certificate.
signing_identity=${Q_CODE_SIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application:/ { print $2; exit }')
fi
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ { print $2; exit }')
fi

if [ -n "$signing_identity" ]; then
    codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$bundle"
else
    codesign --force --deep --sign - "$bundle"
fi

echo "$bundle"

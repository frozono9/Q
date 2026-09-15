#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
binary=${Q_BUILD_BINARY:-"$project_dir/.build/arm64-apple-macosx/$configuration/Q"}
bundle="$project_dir/.build/Q.app"

if [ ! -x "$binary" ]; then
    echo "Missing Q executable at $binary. Build Q first." >&2
    exit 1
fi

if [ -d "$bundle" ]; then
    rm -rf "$bundle"
fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
/usr/bin/ditto "$binary" "$bundle/Contents/MacOS/Q"
/usr/bin/ditto "$project_dir/Config/Info.plist" "$bundle/Contents/Info.plist"
/usr/bin/ditto "$project_dir/Resources/Brand/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$project_dir/Resources/Brand/AppIconAssets.car" "$bundle/Contents/Resources/Assets.car"
/usr/bin/ditto "$project_dir/Resources/Brand/QLogo.png" "$bundle/Contents/Resources/QLogo.png"
/usr/bin/ditto "$project_dir/Resources/Brand/QMenuBarTemplate.png" "$bundle/Contents/Resources/QMenuBarTemplate.png"
/usr/bin/ditto "$project_dir/THIRD_PARTY_NOTICES.md" "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
chmod +x "$bundle/Contents/MacOS/Q"

if [ -n "${Q_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $Q_VERSION" "$bundle/Contents/Info.plist"
fi
if [ -n "${Q_BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $Q_BUILD_NUMBER" "$bundle/Contents/Info.plist"
fi

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
    case "$signing_identity" in
        *"Developer ID Application"*)
            codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$bundle"
            ;;
        *)
            codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$bundle"
            ;;
    esac
else
    codesign --force --deep --sign - "$bundle"
fi

codesign --verify --deep --strict --verbose=2 "$bundle"

echo "$bundle"

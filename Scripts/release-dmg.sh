#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${Q_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Config/Info.plist")}
build_number=${Q_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$project_dir/Config/Info.plist")}

cd "$project_dir"
if swift package dump-package >/dev/null 2>&1; then
    swift build -c release --arch arm64 --arch x86_64
    binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
    echo "SwiftPM manifest runtime is unavailable; using the verified direct-compiler build." >&2
    binary_dir=$(sh "$project_dir/Scripts/build-local.sh" release)
fi

Q_BUILD_BINARY="$binary_dir/Q" \
Q_WATCHER_BINARY="$binary_dir/QDeviceWatcher" \
Q_CLAUDE_HOOK_BINARY="$binary_dir/QClaudeHook" \
Q_VERSION="$version" \
Q_BUILD_NUMBER="$build_number" \
    sh "$project_dir/Scripts/package-app.sh" release >/dev/null

dmg=$(sh "$project_dir/Scripts/create-dmg.sh")

if [ -n "${Q_NOTARY_PROFILE:-}" ]; then
    Q_NOTARY_PROFILE="$Q_NOTARY_PROFILE" sh "$project_dir/Scripts/notarize-dmg.sh" "$dmg" >/dev/null
fi

sh "$project_dir/Scripts/verify-release.sh" "$dmg" >/dev/null

echo "$dmg"

#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${Q_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Config/Info.plist")}
build_number=${Q_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$project_dir/Config/Info.plist")}

cd "$project_dir"
swift build -c release --arch arm64 --arch x86_64
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

Q_BUILD_BINARY="$binary_dir/Q" \
Q_VERSION="$version" \
Q_BUILD_NUMBER="$build_number" \
    sh "$project_dir/Scripts/package-app.sh" release >/dev/null

dmg=$(sh "$project_dir/Scripts/create-dmg.sh")

if [ -n "${Q_NOTARY_PROFILE:-}" ]; then
    Q_NOTARY_PROFILE="$Q_NOTARY_PROFILE" sh "$project_dir/Scripts/notarize-dmg.sh" "$dmg" >/dev/null
fi

echo "$dmg"


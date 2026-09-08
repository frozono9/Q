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
chmod +x "$bundle/Contents/MacOS/Q"

echo "$bundle"

#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

echo "== Source checks =="
git diff --check

echo "== Universal app build =="
binary_dir=$(sh Scripts/build-local.sh release)
file "$binary_dir/Q" "$binary_dir/QDeviceWatcher" "$binary_dir/QClaudeHook"

echo "== QCore reliability checks =="
host_arch=$(uname -m)
sdk=$(xcrun --sdk macosx --show-sdk-path)
check_binary=$(mktemp /tmp/q-core-check.XXXXXX)
trap 'rm -f "$check_binary"' EXIT INT TERM
xcrun swiftc -parse-as-library -target "$host_arch-apple-macos14.0" -sdk "$sdk" \
    -I "$binary_dir/$host_arch" \
    "$project_dir/Scripts/QCoreReliabilityCheck.swift" \
    "$binary_dir/$host_arch/libQCore.a" \
    -o "$check_binary"
"$check_binary"

echo "== Package =="
Q_BUILD_BINARY="$binary_dir/Q" \
Q_WATCHER_BINARY="$binary_dir/QDeviceWatcher" \
Q_CLAUDE_HOOK_BINARY="$binary_dir/QClaudeHook" \
    sh Scripts/package-app.sh release >/dev/null
codesign --verify --deep --strict --verbose=2 .build/Q.app

if command -v pio >/dev/null 2>&1; then
    echo "== Firmware =="
    (cd Firmware && pio run)
else
    echo "== Firmware skipped: PlatformIO not installed =="
fi

echo "Automated checks passed. Complete Docs/RELIABILITY_MATRIX.md on physical hardware."

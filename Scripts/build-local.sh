#!/bin/sh
set -eu

# Direct compiler fallback for Apple Command Line Tools installations where
# swiftc works but PackageDescription is temporarily ABI-incompatible with
# SwiftPM. Produces universal, statically linked Q binaries.
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-release}
output="$project_dir/.build/manual-$configuration"
sdk=$(xcrun --sdk macosx --show-sdk-path)

mkdir -p "$output/arm64" "$output/x86_64"

for arch in arm64 x86_64; do
    arch_output="$output/$arch"
    optimization="-Onone"
    if [ "$configuration" = "release" ]; then optimization="-O"; fi

    # shellcheck disable=SC2046
    xcrun swiftc -parse-as-library -emit-module -emit-library -static \
        -module-name QCore -target "$arch-apple-macos14.0" -sdk "$sdk" \
        $optimization -o "$arch_output/libQCore.a" \
        $(find "$project_dir/Sources/Q/Models" "$project_dir/Sources/Q/Device" -name '*.swift' -print | sort)

    # shellcheck disable=SC2046
    xcrun swiftc -module-name Q -target "$arch-apple-macos14.0" -sdk "$sdk" \
        $optimization -I "$arch_output" -L "$arch_output" -lQCore \
        $(find "$project_dir/Sources/Q/App" "$project_dir/Sources/Q/Integrations" "$project_dir/Sources/Q/UI" -name '*.swift' -print | sort) \
        -o "$arch_output/Q"

    # shellcheck disable=SC2046
    xcrun swiftc -module-name QDeviceWatcher -target "$arch-apple-macos14.0" -sdk "$sdk" \
        $optimization $(find "$project_dir/Sources/QDeviceWatcher" -name '*.swift' -print | sort) \
        -o "$arch_output/QDeviceWatcher"

    # shellcheck disable=SC2046
    xcrun swiftc -module-name QClaudeHook -target "$arch-apple-macos14.0" -sdk "$sdk" \
        $optimization $(find "$project_dir/Sources/QClaudeHook" -name '*.swift' -print | sort) \
        -o "$arch_output/QClaudeHook"
done

lipo -create "$output/arm64/Q" "$output/x86_64/Q" -output "$output/Q"
lipo -create "$output/arm64/QDeviceWatcher" "$output/x86_64/QDeviceWatcher" -output "$output/QDeviceWatcher"
lipo -create "$output/arm64/QClaudeHook" "$output/x86_64/QClaudeHook" -output "$output/QClaudeHook"
echo "$output"

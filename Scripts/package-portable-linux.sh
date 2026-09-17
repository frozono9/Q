#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
binary_dir=$(swift build --configuration release --show-bin-path)
package="$project_dir/.build/packages/q-linux-x86_64"
test ! -e "$package"
mkdir -p "$package/lib" "$package/licenses"
cp "$binary_dir/q" "$package/q-bin"
# ldd includes transitive dependencies. Bundle the Swift toolchain's libraries;
# glibc and system libraries remain the declared Ubuntu 24.04 baseline.
ldd "$binary_dir/q" | awk '/=> \/.*swift/ {print $3}' | while IFS= read -r library; do
    cp -L "$library" "$package/lib/"
done
cat > "$package/q" <<'WRAPPER'
#!/bin/sh
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$directory/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$directory/q-bin" "$@"
WRAPPER
chmod +x "$package/q" "$package/q-bin"
cp Docs/PORTABLE_CLI.md "$package/README.md"
cp Docs/PORTABLE_RUNTIME_NOTICES.md "$package/"
curl -fsSL https://raw.githubusercontent.com/swiftlang/swift/swift-6.1.2-RELEASE/LICENSE.txt -o "$package/licenses/Swift-LICENSE.txt"
git rev-parse HEAD > "$package/COMMIT.txt"
"$package/q" --help
"$package/q" list
tar -czf .build/packages/q-linux-x86_64.tar.gz -C .build/packages q-linux-x86_64
sha256sum .build/packages/q-linux-x86_64.tar.gz

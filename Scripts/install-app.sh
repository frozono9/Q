#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
packaged_app="$project_dir/.build/Q.app"
installed_app="/Applications/Q.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

sh "$project_dir/Scripts/package-app.sh" "$configuration" >/dev/null

# Stop an older development or installed copy so macOS launches this bundle.
pkill -x Q 2>/dev/null || true
/usr/bin/ditto --rsrc --extattr "$packaged_app" "$installed_app"
"$launch_services" -f "$installed_app"
/usr/bin/open -n "$installed_app"

echo "Installed and opened $installed_app"

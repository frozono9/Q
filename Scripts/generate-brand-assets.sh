#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_art="$project_dir/Resources/Brand/qgadget.png"
output_dir="$project_dir/Resources/Brand"

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to regenerate Q's brand assets." >&2
    exit 1
fi

if [ ! -f "$source_art" ]; then
    echo "Missing source artwork at $source_art" >&2
    exit 1
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Crop only the supplied mark, retaining its original antialiasing and transparency.
magick "$source_art" \
    -crop 850x850+202+202 +repage \
    -resize 768x768 \
    -gravity center -background none -extent 768x768 \
    -strip "$output_dir/QLogo.png"

# macOS recolors template images automatically for light, dark, selected, and
# high-contrast menu-bar appearances.
magick "$output_dir/QLogo.png" \
    -resize 64x64 \
    -gravity center -background none -extent 72x72 \
    -strip "$output_dir/QMenuBarTemplate.png"

# Build a calm macOS-style icon tile around the user's original black mark.
magick -size 1024x1024 xc:none \
    -fill '#00000030' \
    -draw 'roundrectangle 86,96 938,950 188,188' \
    -blur 0x28 "$work_dir/shadow.png"

magick -size 1024x1024 gradient:'#FCFBF7-#E8E5DC' \
    \( -size 1024x1024 xc:none -fill white \
       -draw 'roundrectangle 72,72 952,952 196,196' \) \
    -alpha off -compose CopyOpacity -composite "$work_dir/tile.png"

magick "$output_dir/QLogo.png" -resize 610x610 "$work_dir/mark.png"
magick "$work_dir/shadow.png" "$work_dir/tile.png" \
    -compose over -composite \
    "$work_dir/mark.png" -gravity center -geometry +0-2 \
    -compose over -composite \
    -strip "$output_dir/AppIcon.png"

iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset"
for specification in \
    '16 icon_16x16.png' \
    '32 icon_16x16@2x.png' \
    '32 icon_32x32.png' \
    '64 icon_32x32@2x.png' \
    '128 icon_128x128.png' \
    '256 icon_128x128@2x.png' \
    '256 icon_256x256.png' \
    '512 icon_256x256@2x.png' \
    '512 icon_512x512.png' \
    '1024 icon_512x512@2x.png'
do
    set -- $specification
    magick "$output_dir/AppIcon.png" -resize "$1"x"$1" "$iconset/$2"
done

iconutil -c icns "$iconset" -o "$output_dir/AppIcon.icns"
echo "Regenerated Q brand assets in $output_dir"

#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
iconset_dir="$project_dir/.build/AppIcon.iconset"
output_file="$project_dir/Resources/AppIcon.icns"

/bin/rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"
xcrun swift "$project_dir/scripts/generate-icon.swift" "$iconset_dir"
if command -v pngquant >/dev/null 2>&1; then
    pngquant --force --speed 1 --quality 75-90 --ext .png -- "$iconset_dir"/*.png
fi
iconutil -c icns "$iconset_dir" -o "$output_file"

echo "$output_file"

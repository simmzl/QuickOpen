#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/QuickOpen.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
architectures=(${QUICKOPEN_ARCHS:-arm64 x86_64})
binary_paths=()

"$project_dir/scripts/generate-icon.sh"

for architecture in "${architectures[@]}"; do
    MACOSX_DEPLOYMENT_TARGET=13.0 swift build \
        --package-path "$project_dir" \
        --configuration release \
        --arch "$architecture" \
        -Xswiftc -Osize \
        -Xlinker -dead_strip
    binary_dir="$(swift build \
        --package-path "$project_dir" \
        --configuration release \
        --arch "$architecture" \
        --show-bin-path)"
    binary_paths+=("$binary_dir/QuickOpen")
done

/bin/rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$resources_dir"
if [ "${#binary_paths[@]}" -eq 1 ]; then
    cp "${binary_paths[0]}" "$contents_dir/MacOS/QuickOpen"
else
    lipo -create "${binary_paths[@]}" -output "$contents_dir/MacOS/QuickOpen"
fi
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
strip -x "$contents_dir/MacOS/QuickOpen"
plutil -lint "$contents_dir/Info.plist"

signing_identity="${QUICKOPEN_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -1)"
fi

if [ -n "$signing_identity" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
    echo "Signed with: $signing_identity"
else
    codesign --force --deep --options runtime --sign - "$app_dir"
    echo "Warning: no Developer ID Application certificate found; using ad-hoc signing."
fi

echo "$app_dir"

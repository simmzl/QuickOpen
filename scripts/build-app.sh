#!/usr/bin/env bash
# Build dist/QuickOpen.app (universal: arm64 + x86_64).
#
# Environment variables (all optional):
#   QUICKOPEN_VERSION            Marketing version, e.g. 1.3.0 (default: value in Resources/Info.plist)
#   QUICKOPEN_BUILD_NUMBER       CFBundleVersion (default: number of commits)
#   QUICKOPEN_ARCHS              Architectures to build (default: "arm64 x86_64")
#   QUICKOPEN_SIGNING_IDENTITY   codesign identity; defaults to the first "Developer ID Application"
#                                certificate in the keychain, otherwise ad-hoc ("-")
#   QUICKOPEN_SKIP_ICON=1        Use the committed Resources/AppIcon.icns instead of regenerating it
#   QUICKOPEN_SWIFTPM_FLAGS      Extra flags for `swift build` (e.g. --disable-sandbox)
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/QuickOpen.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
read -r -a architectures <<< "${QUICKOPEN_ARCHS:-arm64 x86_64}"
read -r -a swiftpm_flags <<< "${QUICKOPEN_SWIFTPM_FLAGS:-}"
binary_paths=()

if [ "${QUICKOPEN_SKIP_ICON:-0}" != "1" ]; then
    "$project_dir/scripts/generate-icon.sh"
fi

for architecture in "${architectures[@]}"; do
    MACOSX_DEPLOYMENT_TARGET=13.0 swift build \
        --package-path "$project_dir" \
        --configuration release \
        --arch "$architecture" \
        ${swiftpm_flags[@]+"${swiftpm_flags[@]}"} \
        -Xswiftc -Osize \
        -Xlinker -dead_strip
    binary_dir="$(swift build \
        --package-path "$project_dir" \
        --configuration release \
        --arch "$architecture" \
        ${swiftpm_flags[@]+"${swiftpm_flags[@]}"} \
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

# Version numbers
if [ -n "${QUICKOPEN_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${QUICKOPEN_VERSION#v}" "$contents_dir/Info.plist"
fi
build_number="${QUICKOPEN_BUILD_NUMBER:-$(git -C "$project_dir" rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"

strip -x "$contents_dir/MacOS/QuickOpen"
plutil -lint "$contents_dir/Info.plist"

signing_identity="${QUICKOPEN_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -1)"
fi

if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
    echo "Signed with: $signing_identity"
else
    codesign --force --deep --options runtime --sign - "$app_dir"
    echo "Warning: no Developer ID Application certificate found; using ad-hoc signing."
fi
codesign --verify --deep --strict "$app_dir"

echo "Built $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$contents_dir/Info.plist") ($build_number): $app_dir"

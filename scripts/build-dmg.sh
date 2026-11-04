#!/usr/bin/env bash
# Build dist/QuickOpen.app, then package dist/QuickOpen-<version>.dmg and .zip.
#
# Accepts every variable of build-app.sh, plus:
#   QUICKOPEN_NOTARY_PROFILE   notarytool keychain profile (local use)
#   QUICKOPEN_NOTARY_KEY       Path to an App Store Connect API key (.p8) (CI use) …
#   QUICKOPEN_NOTARY_KEY_ID    … its Key ID …
#   QUICKOPEN_NOTARY_ISSUER    … and Issuer ID.
# Notarization runs only when the app is signed with a Developer ID certificate
# and one of the credential sets above is provided.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$project_dir/dist/QuickOpen.app"
staging_dir="$project_dir/.build/dmg-root"

"$project_dir/scripts/build-app.sh"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
dmg_path="$project_dir/dist/QuickOpen-$version.dmg"
zip_path="$project_dir/dist/QuickOpen-$version.zip"

signing_identity="$(codesign -dvv "$app_path" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' | head -1)"

notarize() {
    local file="$1"
    if [ -n "${QUICKOPEN_NOTARY_KEY:-}" ]; then
        xcrun notarytool submit "$file" \
            --key "$QUICKOPEN_NOTARY_KEY" \
            --key-id "$QUICKOPEN_NOTARY_KEY_ID" \
            --issuer "$QUICKOPEN_NOTARY_ISSUER" \
            --wait
    else
        xcrun notarytool submit "$file" --keychain-profile "$QUICKOPEN_NOTARY_PROFILE" --wait
    fi
}

should_notarize=0
if [ -n "$signing_identity" ] && { [ -n "${QUICKOPEN_NOTARY_KEY:-}" ] || [ -n "${QUICKOPEN_NOTARY_PROFILE:-}" ]; }; then
    should_notarize=1
fi

# Notarize the app first (via a zip) so the stapled ticket ends up inside both the dmg and the zip.
if [ "$should_notarize" = "1" ]; then
    /bin/rm -f "$zip_path"
    ditto -c -k --keepParent "$app_path" "$zip_path"
    notarize "$zip_path"
    xcrun stapler staple "$app_path"
fi

/bin/rm -f "$zip_path"
ditto -c -k --keepParent "$app_path" "$zip_path"

/bin/rm -rf "$staging_dir"
mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/QuickOpen.app"
ln -s /Applications "$staging_dir/Applications"
/bin/rm -f "$dmg_path"
hdiutil create \
    -volname "QuickOpen" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

if [ -n "$signing_identity" ]; then
    codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
fi
if [ "$should_notarize" = "1" ]; then
    notarize "$dmg_path"
    xcrun stapler staple "$dmg_path"
fi

(cd "$project_dir/dist" && shasum -a 256 "$(basename "$dmg_path")" "$(basename "$zip_path")" > "QuickOpen-$version.sha256")
echo "$dmg_path"
echo "$zip_path"

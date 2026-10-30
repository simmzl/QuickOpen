#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$project_dir/dist/QuickOpen.app"
dmg_path="$project_dir/dist/QuickOpen.dmg"
staging_dir="$project_dir/.build/dmg-root"

"$project_dir/scripts/build-app.sh"

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

signing_identity="${QUICKOPEN_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -1)"
fi
if [ -n "$signing_identity" ]; then
    codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
fi

if [ -n "${QUICKOPEN_NOTARY_PROFILE:-}" ]; then
    if [ -z "$signing_identity" ]; then
        echo "Error: notarization requires a Developer ID Application certificate." >&2
        exit 1
    fi
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$QUICKOPEN_NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$dmg_path"
fi

echo "$dmg_path"

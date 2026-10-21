#!/bin/sh
# Builds a signed, notarized build/Termos.zip that opens on any Mac with macOS 14 or later.
# Usage: TERMOS_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh
#
# Needs notarytool credentials stored once in the keychain under $TERMOS_NOTARY_PROFILE
# (default: termos):
#   xcrun notarytool store-credentials termos --apple-id you@example.com --team-id TEAMID
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Termos.app"
ZIP="$ROOT/build/Termos.zip"
PROFILE="${TERMOS_NOTARY_PROFILE:-termos}"

case "${TERMOS_SIGN_IDENTITY:-}" in
    "Developer ID Application:"*) ;;
    *) echo "Set TERMOS_SIGN_IDENTITY to a \"Developer ID Application: …\" identity." >&2; exit 1 ;;
esac

"$ROOT/scripts/bundle.sh" release

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Attach the notarization ticket so the app also opens offline, then zip the stapled app.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP"
echo "Built $ZIP"

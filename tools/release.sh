#!/bin/zsh
# Builds Snapr, signs it with Developer ID, notarizes it with Apple, and
# writes dist/Snapr.zip, ready to send to other people.
#
# Needs once (see docs/RELEASE.md):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. A notarytool profile:  xcrun notarytool store-credentials snapr-notary
# Usage: tools/release.sh            (NOTARY_PROFILE=snapr-notary by default)
set -euo pipefail
here=${0:A:h:h}
profile="${NOTARY_PROFILE:-snapr-notary}"
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)}"
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate found. See docs/RELEASE.md."; exit 1; }

# Same app as build.sh, signed with the Developer ID and the hardened runtime.
SIGN_IDENTITY="$identity" "$here/build.sh" >/dev/null
app=/Applications/Snapr.app
codesign --force --timestamp --options runtime --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

mkdir -p "$here/dist"
zip="$here/dist/Snapr.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
# Zip again so the ticket travels with the app.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "ready: $zip"

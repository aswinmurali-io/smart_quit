#!/bin/bash
#
# Packages dist/Smart Quit.app into dist/SmartQuit.dmg.
#
# This is the packaging half of a release, split out so a disk image can be
# built with whatever signature the app already has. Scripts/release.sh calls it
# and then notarizes the result; run directly, it produces a disk image that
# installs fine on this Mac and trips Gatekeeper on anyone else's — see the note
# it prints at the end.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Smart Quit"
BUNDLE="dist/${APP_NAME}.app"
DMG="dist/SmartQuit.dmg"
STAGING="build/dmg"

if [[ ! -d "${BUNDLE}" ]]; then
    echo "==> No app bundle yet"
    ./Scripts/build-app.sh
fi

echo "==> Staging"
rm -rf "${STAGING}" "${DMG}"
mkdir -p "${STAGING}"
cp -R "${BUNDLE}" "${STAGING}/"
# A symlink to /Applications, so the disk image is a drag-and-drop installer
# rather than something the user has to know where to put.
ln -s /Applications "${STAGING}/Applications"

echo "==> Building ${DMG}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG}" >/dev/null

rm -rf "${STAGING}"

# Report what this disk image will actually do on someone else's Mac, rather
# than leaving them to discover it from a "damaged" dialog. spctl answers the
# question Gatekeeper asks; a non-zero exit here is information, not a failure.
echo
if spctl --assess --type open --context context:primary-signature "${DMG}" 2>/dev/null; then
    echo "Notarized: this installs cleanly anywhere."
else
    echo "Built ${DMG} — NOT notarized."
    echo
    echo "It installs fine on this Mac. On any other Mac, macOS will refuse it:"
    echo "downloading it attaches a quarantine flag, and an unnotarized app under"
    echo "quarantine is reported as damaged rather than merely untrusted."
    echo
    echo "To share it, run ./Scripts/release.sh instead — that needs a Developer ID"
    echo "certificate and a notarytool profile. To open this one on another Mac,"
    echo "the quarantine flag has to be cleared by hand:"
    echo "  xattr -d com.apple.quarantine /path/to/SmartQuit.dmg"
fi

echo
ls -lh "${DMG}"

#!/bin/bash
#
# Builds, signs, notarizes and staples SmartQuit-<version>.dmg for distribution.
#
# Scripts/build-app.sh signs with an Apple Development certificate, which is
# enough to run the app on the machine that built it. Handing it to anyone else
# needs a Developer ID Application certificate and a trip through Apple's
# notary service — without both, Gatekeeper refuses the app outright on a
# machine that has never seen it, and the user gets "Smart Quit is damaged"
# rather than anything actionable.
#
# Requires:
#   - A "Developer ID Application" certificate in the keychain, which comes with
#     a paid Apple Developer Program membership.
#   - A notarytool keychain profile. Create one once with:
#       xcrun notarytool store-credentials smartquit-notary \
#         --apple-id <your-apple-id> --team-id <your-team-id> \
#         --password <an app-specific password from appleid.apple.com>
#
# Override the defaults with DEVELOPER_ID and NOTARY_PROFILE.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Smart Quit"
BUNDLE="dist/${APP_NAME}.app"
# Derived the same way as in make-dmg.sh, from the same file, so the image this
# notarizes is the one that was just built.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="dist/SmartQuit-${VERSION}.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-smartquit-notary}"
ENTITLEMENTS="Resources/SmartQuit.entitlements"

# MARK: Preflight
#
# Both checks are here rather than left to fail deep inside codesign or
# notarytool, where the errors name neither the missing certificate nor the
# missing profile.

DEVELOPER_ID="${DEVELOPER_ID:-}"
if [[ -z "${DEVELOPER_ID}" ]]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning \
        | grep -m1 '"Developer ID Application' \
        | sed -E 's/.*"(.*)"/\1/' || true)"
fi

if [[ -z "${DEVELOPER_ID}" ]]; then
    echo "error: no Developer ID Application certificate in the keychain." >&2
    echo "       It comes with a paid Apple Developer Program membership;" >&2
    echo "       download it from developer.apple.com and add it to the keychain." >&2
    echo "       Scripts/build-app.sh still builds a locally runnable app without it." >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "error: no notarytool profile named '${NOTARY_PROFILE}'." >&2
    echo "       Create one with:" >&2
    echo "         xcrun notarytool store-credentials ${NOTARY_PROFILE} \\" >&2
    echo "           --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
    exit 1
fi

# MARK: Build

echo "==> Building the app"
CODESIGN_IDENTITY="${DEVELOPER_ID}" ./Scripts/build-app.sh

# MARK: Sign for distribution
#
# The hardened runtime is a precondition for notarization. Smart Quit does not
# load third-party plug-ins or run unsigned code, so it needs no exceptions
# beyond the entitlements file, which exists so the set is explicit rather than
# implied by its absence.

echo "==> Signing for distribution"
codesign --force --deep \
    --sign "${DEVELOPER_ID}" \
    --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    --timestamp \
    "${BUNDLE}"

codesign --verify --strict --verbose=2 "${BUNDLE}"

# MARK: Package

./Scripts/make-dmg.sh

# MARK: Sign the container
#
# Signed after the image is built, never before: hdiutil rewrites the file when
# it converts to the compressed format, which drops any signature already there.
# make-dmg.sh leaves it unsigned for that reason, and because an image it builds
# on its own is not distributable anyway.
#
# The identifier is pinned. Left to itself codesign derives one from the file
# name and truncates at the first dot, so SmartQuit-0.1.0.dmg signs as
# "SmartQuit-0" — a different identifier every release, and a wrong-looking one.
#
# A real --timestamp, not --timestamp=none: notarization rejects a signature
# without a secure timestamp.

echo "==> Signing the disk image"
codesign --force \
    --sign "${DEVELOPER_ID}" \
    --identifier "com.smartquit.SmartQuit.dmg" \
    --timestamp \
    "${DMG}"

codesign --verify --verbose=2 "${DMG}"

# MARK: Notarize
#
# The disk image is submitted rather than the app: stapling to the .dmg means a
# user who downloads it can be checked offline, where stapling to the app alone
# leaves the container unverified.

echo "==> Notarizing (this takes a few minutes)"
xcrun notarytool submit "${DMG}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "==> Stapling"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

# The check a first-time user's machine actually performs.
echo "==> Verifying as Gatekeeper would"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"

echo
echo "Built ${DMG}"

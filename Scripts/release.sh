#!/bin/bash
# SPDX-FileCopyrightText: 2026 Aswin Murali
# SPDX-License-Identifier: GPL-3.0-only
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

# shellcheck source=Scripts/signing-identity.sh
source "Scripts/signing-identity.sh"

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

# Chosen through the same code as Scripts/build-app.sh. This used to pick the
# first Developer ID with `grep -m1` while build-app.sh refused an ambiguous
# match — so a keychain with two of them could have the two scripts sign one
# bundle with different certificates, producing different code requirements and
# taking the Accessibility grant with them, both scripts reporting success.
CODESIGN_IDENTITY="${DEVELOPER_ID:-${CODESIGN_IDENTITY:-}}"
if smartquit_select_identity "Developer ID Application"; then
    DEVELOPER_ID="${SIGNING_IDENTITY}"
else
    if [[ -n "${SIGNING_CANDIDATES}" ]]; then
        echo "error: more than one Developer ID Application certificate matched." >&2
        echo "       Set DEVELOPER_ID to one of these:" >&2
        sed 's/^/         /' >&2 <<< "${SIGNING_CANDIDATES}"
    else
        echo "error: no Developer ID Application certificate in the keychain." >&2
        echo "       It comes with a paid Apple Developer Program membership;" >&2
        echo "       download it from developer.apple.com and add it to the keychain." >&2
        echo "       Scripts/build-app.sh still builds a locally runnable app without it." >&2
    fi
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

# Not --deep: Apple documents it as a verification convenience and warns
# against signing with it, because it stamps every nested binary with the
# same entitlements instead of signing each on its own terms. There is no
# nested code here today, and this is where that would quietly stop being
# true.
echo "==> Signing for distribution"
codesign --force \
    --sign "${DEVELOPER_ID}" \
    --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    --timestamp \
    "${BUNDLE}"

codesign --verify --strict --verbose=2 "${BUNDLE}"

# The signature this script applies must produce the same code requirement as
# the one build-app.sh applied a moment ago, or a user who approved a locally
# built copy loses the grant on installing the release — the very drift the
# shared identity selection exists to prevent. The hardened runtime and the
# entitlements added above do not enter the requirement, so this is an equality
# and not an approximation. Checked rather than assumed, because it is exactly
# the kind of invariant that holds until someone edits one script.
RELEASE_REQUIREMENT="$(smartquit_designated_requirement "${BUNDLE}")"
BUILD_REQUIREMENT="$(cat build/last-signing-requirement 2>/dev/null || true)"
if [[ -n "${BUILD_REQUIREMENT}" && "${RELEASE_REQUIREMENT}" != "${BUILD_REQUIREMENT}" ]]; then
    echo "error: this signature does not match the one build-app.sh just applied." >&2
    echo "       build-app.sh: ${BUILD_REQUIREMENT}" >&2
    echo "       release.sh:   ${RELEASE_REQUIREMENT}" >&2
    echo "       Installing this release would end the Accessibility grant of" >&2
    echo "       anyone running a locally built copy. The two scripts have" >&2
    echo "       drifted; both select through Scripts/signing-identity.sh." >&2
    exit 1
fi

# MARK: Package

SMARTQUIT_WILL_NOTARIZE=1 ./Scripts/make-dmg.sh

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

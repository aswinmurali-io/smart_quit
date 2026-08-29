#!/bin/bash
#
# Builds "Smart Quit.app" into dist/.
#
# Swift Package Manager produces a bare executable; a menu bar app needs a
# bundle so that LSUIElement, the bundle identifier, and SMAppService
# registration all work. This script assembles that bundle and signs it.
#
# Set CODESIGN_IDENTITY to name the signing identity outright, or
# SMARTQUIT_SIGNING_ACCOUNT to pick one by Apple ID. With neither, and no
# matching certificate, the build falls back to an ad-hoc signature — see the
# note under Signing for what that costs.

set -euo pipefail

cd "$(dirname "$0")/.."

# The product name has a space; the executable, module and bundle identifier
# do not. Keeping them apart means the name shown to a person can change
# without touching a build setting or a code identifier.
APP_NAME="Smart Quit"
TARGET="SmartQuit"
CONFIGURATION="release"
BUNDLE="dist/${APP_NAME}.app"
ICON="Resources/${TARGET}.icns"

echo "==> Building ${CONFIGURATION}"
swift build --configuration "${CONFIGURATION}"

BINARY="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)/${TARGET}"
if [[ ! -x "${BINARY}" ]]; then
    echo "error: built executable not found at ${BINARY}" >&2
    exit 1
fi

if [[ ! -f "${ICON}" ]]; then
    echo "==> Drawing ${ICON}"
    mkdir -p build
    swift Scripts/make-icon.swift
    iconutil -c icns "build/${TARGET}.iconset" -o "${ICON}"
fi

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BINARY}" "${BUNDLE}/Contents/MacOS/${TARGET}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp "${ICON}" "${BUNDLE}/Contents/Resources/${TARGET}.icns"

# Signing.
#
# The Accessibility grant is keyed to the signature. An ad-hoc signature changes
# its cdhash on every build, so macOS stops recognising the app as the one the
# user approved: the checkbox in System Settings stays ticked while the app is
# told it has no permission, and re-ticking does not help — the stale record has
# to be cleared with `tccutil reset Accessibility com.smartquit.SmartQuit`.
#
# A real certificate gives a stable identity across rebuilds, so the grant
# survives. Any Apple Development certificate will do for local use; shipping to
# other people needs Developer ID, which Scripts/release.sh handles.
# The identity is matched by account rather than by taking the first Apple
# Development certificate in the keychain. A keychain routinely holds work
# certificates whose private keys are not usable here — signing with one fails
# late, with errSecInternalComponent and nothing to say which key it wanted.
SIGNING_ACCOUNT="${SMARTQUIT_SIGNING_ACCOUNT:-aswinmurali.co@gmail.com}"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "${IDENTITY}" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | grep -m1 -F "${SIGNING_ACCOUNT}" \
        | sed -E 's/.*"(.*)"/\1/' || true)"
fi

if [[ -z "${IDENTITY}" ]]; then
    echo "==> Signing (ad-hoc — no certificate found for ${SIGNING_ACCOUNT})"
    echo "    The Accessibility grant will not survive the next rebuild."
    echo "    Clear it with: tccutil reset Accessibility com.smartquit.SmartQuit"
    echo "    Set SMARTQUIT_SIGNING_ACCOUNT or CODESIGN_IDENTITY to use a certificate."
    codesign --force --sign - --timestamp=none "${BUNDLE}"
else
    echo "==> Signing as ${IDENTITY}"
    codesign --force --sign "${IDENTITY}" --timestamp=none "${BUNDLE}"
fi

codesign --verify --verbose "${BUNDLE}"

echo
echo "Built ${BUNDLE}"
echo "Run it with:  open ${BUNDLE}"

#!/bin/bash
#
# Builds SmartQuit.app into dist/.
#
# Swift Package Manager produces a bare executable; a menu bar app needs a
# bundle so that LSUIElement, the bundle identifier, and SMAppService
# registration all work. This script assembles that bundle and ad-hoc signs it.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SmartQuit"
CONFIGURATION="release"
BUNDLE="dist/${APP_NAME}.app"

echo "==> Building ${CONFIGURATION}"
swift build --configuration "${CONFIGURATION}"

BINARY="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BINARY}" ]]; then
    echo "error: built executable not found at ${BINARY}" >&2
    exit 1
fi

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BINARY}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"

# Ad-hoc signature. The Accessibility grant is tied to this signature, so a
# rebuild can require re-granting permission in System Settings.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "${BUNDLE}"
codesign --verify --verbose "${BUNDLE}"

echo
echo "Built ${BUNDLE}"
echo "Run it with:  open ${BUNDLE}"

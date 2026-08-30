#!/bin/bash
# SPDX-FileCopyrightText: 2026 Aswin Murali
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds "Smart Quit.app" into dist/.
#
# Swift Package Manager produces a bare executable; a menu bar app needs a
# bundle so that LSUIElement, the bundle identifier, and SMAppService
# registration all work. This script assembles that bundle and signs it.
#
# Set CODESIGN_IDENTITY to name the signing identity outright, or
# SMARTQUIT_SIGNING_ACCOUNT to pick one by Apple ID. With neither, the build
# uses the keychain's Apple Development certificate when there is exactly one.
# Without a usable certificate the build stops rather than signing ad-hoc;
# SMARTQUIT_ALLOW_ADHOC=1 asks for that anyway — see the note under Signing for
# what it costs.

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
# The identity is taken from the Apple Development certificates only, and only
# when the choice is unambiguous. A keychain routinely holds work certificates
# whose private keys are not usable here — signing with one fails late, with
# errSecInternalComponent and nothing to say which key it wanted. So one
# matching certificate is used, several are refused with the list printed, and
# SMARTQUIT_SIGNING_ACCOUNT narrows the match by Apple ID.
SIGNING_ACCOUNT="${SMARTQUIT_SIGNING_ACCOUNT:-}"

IDENTITY="${CODESIGN_IDENTITY:-}"
CANDIDATES=""
if [[ -z "${IDENTITY}" ]]; then
    CANDIDATES="$(security find-identity -v -p codesigning \
        | grep -F '"Apple Development:' \
        | grep -F "${SIGNING_ACCOUNT}" \
        | sed -E 's/.*"(.*)"/\1/' || true)"
    if [[ "$(grep -c . <<< "${CANDIDATES}")" -eq 1 ]]; then
        IDENTITY="${CANDIDATES}"
    fi
fi

# Signing ad-hoc is a decision, not a fallback.
#
# It was one until it cost an afternoon: an ad-hoc build silently replaced a
# properly signed one, macOS went on showing the app as approved, and the app
# went on being told it had no permission. It quit nothing and said nothing.
# The warning that scrolled past during the build was the only sign, and a
# warning nobody reads is not a choice anyone made. So the build now stops, and
# SMARTQUIT_ALLOW_ADHOC=1 is how the cost gets accepted out loud — CI sets it,
# because a runner has no certificate and no permission to lose.
if [[ -z "${IDENTITY}" ]]; then
    if [[ -n "${CANDIDATES}" ]]; then
        REASON="more than one Apple Development certificate matched"
        ADVICE="Set SMARTQUIT_SIGNING_ACCOUNT to your Apple ID, or CODESIGN_IDENTITY to one of these:"
    else
        REASON="no Apple Development certificate${SIGNING_ACCOUNT:+ for ${SIGNING_ACCOUNT}} in the keychain"
        ADVICE="Set SMARTQUIT_SIGNING_ACCOUNT or CODESIGN_IDENTITY to name one."
    fi

    if [[ "${SMARTQUIT_ALLOW_ADHOC:-0}" != "1" ]]; then
        echo "error: cannot sign — ${REASON}." >&2
        echo "       ${ADVICE}" >&2
        [[ -n "${CANDIDATES}" ]] && sed 's/^/         /' >&2 <<< "${CANDIDATES}"
        echo >&2
        echo "       An ad-hoc signature would build, but its cdhash changes every time," >&2
        echo "       so macOS stops recognising the app as the one you approved: the" >&2
        echo "       checkbox stays ticked while the app is told it has no permission." >&2
        echo "       To accept that anyway: SMARTQUIT_ALLOW_ADHOC=1 $0" >&2
        exit 1
    fi

    echo "==> Signing (ad-hoc — ${REASON})"
    echo "    The Accessibility grant will not survive the next rebuild."
    echo "    Clear it with: tccutil reset Accessibility com.smartquit.SmartQuit"
    codesign --force --sign - --timestamp=none "${BUNDLE}"
    IDENTITY="ad-hoc"
else
    echo "==> Signing as ${IDENTITY}"
    codesign --force --sign "${IDENTITY}" --timestamp=none "${BUNDLE}"
fi

codesign --verify --verbose "${BUNDLE}"

# A changed signature is the moment the Accessibility grant dies.
#
# TCC stores the grant against the code requirement the app had when it was
# approved. Sign with a different identity — ad-hoc to real, Apple Development
# to Developer ID, one Apple ID to another — and the stored requirement no
# longer matches: macOS denies the app while System Settings still shows it
# ticked, and re-ticking does not rebuild the record. Nothing in the app can
# detect this; from inside, a stale grant and a missing one are the same
# refusal. The build is the only place that knows the identity changed, so it
# is the only place that can say so.
STAMP="build/last-signing-identity"
mkdir -p "$(dirname "${STAMP}")"
PREVIOUS="$(cat "${STAMP}" 2>/dev/null || true)"
printf '%s' "${IDENTITY}" > "${STAMP}"

if [[ -n "${PREVIOUS}" && "${PREVIOUS}" != "${IDENTITY}" ]]; then
    echo
    echo "!!  The signing identity changed since the last build."
    echo "      was: ${PREVIOUS}"
    echo "      now: ${IDENTITY}"
    echo "    macOS will refuse this build's Accessibility permission and show it"
    echo "    as granted anyway. Clear the stale record and approve it once more:"
    echo "      tccutil reset Accessibility com.smartquit.SmartQuit"
fi

echo
echo "Built ${BUNDLE}"
echo "Run it with:  open ${BUNDLE}"

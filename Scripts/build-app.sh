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

# shellcheck source=Scripts/signing-identity.sh
source "Scripts/signing-identity.sh"

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
# survives. Developer ID is preferred over Apple Development, and the reason is
# not distribution — it is what TCC stores. The requirement recorded for an
# Apple Development signature pins the leaf certificate's common name:
#
#   ... certificate leaf[subject.CN] = "Apple Development: you@example.com (CFHD58CZ5M)"
#
# where a Developer ID signature pins the team and nothing narrower:
#
#   ... certificate leaf[subject.OU] = WMY7XK75RC
#
# So an Apple Development grant dies when that certificate is reissued, and dies
# again every time Scripts/release.sh signs the same bundle with Developer ID
# for a release — twice per cycle on the machine that does both. Signing here
# with the identity release.sh already uses means one requirement, approved once
# and surviving rebuilds, releases and certificate renewals alike.
#
# Apple Development is still accepted, for a contributor who has one and no
# Developer ID. It costs a re-approval whenever that certificate changes, which
# is the tier's price rather than a fault in it.
#
# How the identity is chosen — the tiers, the ambiguity rule and why the choice
# is never guessed at — lives in Scripts/signing-identity.sh, because
# Scripts/release.sh has to make the same choice and the two drifting apart is
# itself a way the grant dies.
SIGNING_ACCOUNT="${SMARTQUIT_SIGNING_ACCOUNT:-}"

TIERS=("Developer ID Application" "Apple Development")

IDENTITY=""
CANDIDATES=""
KIND=""
if smartquit_select_identity "${TIERS[@]}"; then
    IDENTITY="${SIGNING_IDENTITY}"
fi
CANDIDATES="${SIGNING_CANDIDATES}"
KIND="${SIGNING_KIND}"

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
        REASON="more than one ${KIND} certificate matched"
        ADVICE="Set SMARTQUIT_SIGNING_ACCOUNT to narrow the match, or CODESIGN_IDENTITY to one of these:"
    else
        REASON="no Developer ID Application or Apple Development certificate\
${SIGNING_ACCOUNT:+ for ${SIGNING_ACCOUNT}} in the keychain"
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
# approved. Sign in a way that produces a different requirement and the stored
# one matches nothing: macOS denies the app while System Settings still shows it
# ticked, and re-ticking does not rebuild the record. Nothing in the app can
# detect this; from inside, a stale grant and a missing one are the same
# refusal. The build is the only place that can see it coming, so it is the only
# place that can say so.
#
# What gets compared is the designated requirement itself, not the name of the
# identity that produced it. The name is a proxy, and this codebase has now been
# bitten twice by a proxy read as the real thing — a subrole that could not be
# read counted as a window that was not there, and an identity name counted as
# the requirement derived from it. Comparing the requirement fires exactly when
# the grant dies and stays quiet otherwise, without anyone having to reason
# about what a certificate kind implies.
STAMP_DIR="build"
IDENTITY_STAMP="${STAMP_DIR}/last-signing-identity"
REQUIREMENT_STAMP="${STAMP_DIR}/last-signing-requirement"
mkdir -p "${STAMP_DIR}"

REQUIREMENT="$(smartquit_designated_requirement "${BUNDLE}")"
PREVIOUS_IDENTITY="$(cat "${IDENTITY_STAMP}" 2>/dev/null || true)"
PREVIOUS_REQUIREMENT="$(cat "${REQUIREMENT_STAMP}" 2>/dev/null || true)"
printf '%s' "${IDENTITY}" > "${IDENTITY_STAMP}"
printf '%s' "${REQUIREMENT}" > "${REQUIREMENT_STAMP}"

# An ad-hoc requirement is a cdhash and so differs on every build by design.
# The ad-hoc branch above has already said what that costs; saying it twice
# would train the reader to skip both.
if [[ "${IDENTITY}" != "ad-hoc" &&
      -n "${PREVIOUS_REQUIREMENT}" &&
      "${PREVIOUS_REQUIREMENT}" != "${REQUIREMENT}" ]]; then
    echo
    echo "!!  The code requirement changed since the last build."
    echo "      was: ${PREVIOUS_IDENTITY:-unknown}"
    echo "      now: ${IDENTITY}"
    echo "    macOS will refuse this build's Accessibility permission and show it"
    echo "    as granted anyway. Clear the stale record and approve it once more:"
    echo "      tccutil reset Accessibility com.smartquit.SmartQuit"
fi

# Falling back a tier is the one failure that arrives on a date rather than
# from an edit, and it is silent by construction: an expired Developer ID stops
# being listed, the search drops to Apple Development, and everything reports
# success while the grant dies. Naming the likely cause here saves working back
# from "permission stopped working" to a certificate that lapsed weeks ago.
if [[ "${PREVIOUS_IDENTITY}" == "Developer ID Application"* &&
      "${IDENTITY}" != "Developer ID Application"* ]]; then
    echo
    echo "!!  The last build used a Developer ID certificate and this one did not."
    echo "    If you did not ask for that, the Developer ID has most likely"
    echo "    expired or been removed — check with:"
    echo "      security find-identity -v -p codesigning"
fi

if [[ "${IDENTITY}" == "Developer ID Application"* ]] &&
   smartquit_identity_expires_within "${IDENTITY}" 30; then
    echo
    echo "!!  This Developer ID certificate expires within 30 days."
    echo "    When it does, this build stops finding it and signs with whatever"
    echo "    is left, which ends the Accessibility grant without an error."
    echo "    Renew it at developer.apple.com before then."
fi

echo
echo "Built ${BUNDLE}"
echo "Run it with:  open ${BUNDLE}"

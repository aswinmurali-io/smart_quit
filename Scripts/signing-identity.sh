#!/bin/bash
# SPDX-FileCopyrightText: 2026 Aswin Murali
# SPDX-License-Identifier: GPL-3.0-only
#
# Signing identity selection, shared by Scripts/build-app.sh and
# Scripts/release.sh. Sourced, never run.
#
# It lives in one file because the two scripts choosing separately is a way the
# Accessibility grant dies quietly. They had already drifted: build-app.sh
# refused an ambiguous match while release.sh took the first one with `grep -m1`,
# so a keychain holding two Developer ID certificates could have them sign the
# same bundle with different ones. TCC stores the code requirement, the two
# requirements differ, and the grant goes — with both scripts reporting success.
# Two copies of this logic cannot be held in agreement by intention alone.

# Selects a signing identity from the given certificate kinds, tried in order.
#
# Sets SIGNING_IDENTITY, SIGNING_KIND (the tier the candidates came from) and
# SIGNING_CANDIDATES (every match in that tier, one per line). Returns non-zero
# when there is no single unambiguous match, leaving the caller to report it:
# the two scripts have different advice to give about the same failure.
#
# The identity is never guessed at. A keychain routinely holds work certificates
# whose private keys are not usable here — signing with one fails late, with
# errSecInternalComponent and nothing to say which key it wanted.
#
# Ambiguity inside a tier stops there rather than falling through to the next.
# Two Developer ID certificates is a question to answer, and answering it by
# quietly signing with a weaker identity would spend the grant to avoid asking.
smartquit_select_identity() {
    local account="${SMARTQUIT_SIGNING_ACCOUNT:-}"
    local kind

    SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
    SIGNING_CANDIDATES=""
    SIGNING_KIND=""

    if [[ -n "${SIGNING_IDENTITY}" ]]; then
        SIGNING_KIND="CODESIGN_IDENTITY"
        return 0
    fi

    for kind in "$@"; do
        SIGNING_KIND="${kind}"
        SIGNING_CANDIDATES="$(security find-identity -v -p codesigning \
            | grep -F "\"${kind}:" \
            | grep -F "${account}" \
            | sed -E 's/.*"(.*)"/\1/' || true)"
        if [[ -n "${SIGNING_CANDIDATES}" ]]; then
            break
        fi
    done

    if [[ "$(grep -c . <<< "${SIGNING_CANDIDATES}")" -eq 1 ]]; then
        SIGNING_IDENTITY="${SIGNING_CANDIDATES}"
        return 0
    fi

    SIGNING_IDENTITY=""
    return 1
}

# Whether a certificate is within `days` of expiring. True is exit status 0.
#
# This is the one failure that arrives on a date rather than from an edit.
# `security find-identity -v` lists valid identities only, so an expired
# Developer ID does not fail the build: it silently stops matching, the search
# falls through to the next tier, the bundle is signed with a different
# certificate and the Accessibility grant dies with nothing printed. A warning
# beforehand is the only notice there is going to be.
#
# `openssl x509 -checkend` is asked rather than parsing `notAfter`, whose format
# has a padded day field that trips `date -j -f` on single-digit days.
smartquit_identity_expires_within() {
    local identity="$1" days="${2:-30}"
    local pem

    pem="$(security find-certificate -c "${identity}" -p 2>/dev/null || true)"
    [[ -n "${pem}" ]] || return 1

    ! openssl x509 -checkend "$(( days * 86400 ))" -noout <<< "${pem}" >/dev/null 2>&1
}

# The designated requirement a signed bundle carries.
#
# This is the string TCC stores when the user approves the app, and the string
# it evaluates every later launch against. It is the thing that actually has to
# stay stable — the identity's name is a proxy for it, and a proxy is what let
# the original problem hide.
smartquit_designated_requirement() {
    codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p'
}

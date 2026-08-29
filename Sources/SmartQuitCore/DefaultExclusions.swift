// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Apps excluded on first run.
///
/// These are the ones people habitually leave running with no window open — a
/// mail client fetching in the background, a terminal whose window was closed
/// but whose session matters.
///
/// Spotify is deliberately absent. An app that is playing audio has its clock
/// held for as long as it plays, which covers a music player far better than an
/// exclusion: it protects the music without leaving the app running forever
/// once the music stops. Music is still listed because it also serves a local
/// library that the user may be mid-way through organising.
public enum DefaultExclusions {
    public static let bundleIDs: Set<String> = [
        "com.apple.Music",           // Music
        "com.apple.mail",            // Mail
        "com.apple.MobileSMS",       // Messages
        "com.apple.iCal",            // Calendar
        "com.apple.ActivityMonitor", // Activity Monitor
        "com.apple.Terminal",        // Terminal
        "com.googlecode.iterm2",     // iTerm
    ]
}

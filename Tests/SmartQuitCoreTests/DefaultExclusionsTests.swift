// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class DefaultExclusionsTests: XCTestCase {
    func testExcludesTheAppsThatAreMeantToStayRunning() {
        XCTAssertEqual(
            DefaultExclusions.bundleIDs,
            [
                "com.apple.Music",          // Music
                "com.apple.mail",           // Mail
                "com.apple.MobileSMS",      // Messages
                "com.apple.iCal",           // Calendar
                "com.apple.ActivityMonitor",// Activity Monitor
                "com.apple.Terminal",       // Terminal
                "com.googlecode.iterm2",    // iTerm
            ]
        )
    }

    /// Spotify is not excluded: the audio pause covers it, and excluding it
    /// would leave it running forever once the music stopped.
    func testDoesNotExcludeSpotify() {
        XCTAssertFalse(DefaultExclusions.bundleIDs.contains("com.spotify.client"))
    }
}

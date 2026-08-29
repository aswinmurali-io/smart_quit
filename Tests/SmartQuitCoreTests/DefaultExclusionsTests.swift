import XCTest
@testable import SmartQuitCore

final class DefaultExclusionsTests: XCTestCase {
    func testExcludesTheAppsThatAreMeantToStayRunning() {
        XCTAssertEqual(
            DefaultExclusions.bundleIDs,
            [
                "com.spotify.client",       // Spotify
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
}

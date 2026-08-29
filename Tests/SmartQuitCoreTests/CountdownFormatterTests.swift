// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class CountdownFormatterTests: XCTestCase {
    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(CountdownFormatter.string(for: 135), "2m 15s")
    }

    func testPadsSecondsSoTheLabelDoesNotJitter() {
        XCTAssertEqual(CountdownFormatter.string(for: 125), "2m 05s")
    }

    func testFormatsSecondsAloneUnderAMinute() {
        XCTAssertEqual(CountdownFormatter.string(for: 45), "45s")
    }

    func testFormatsExactlyOneMinute() {
        XCTAssertEqual(CountdownFormatter.string(for: 60), "1m 00s")
    }

    func testFormatsHoursAndMinutesForLongGracePeriods() {
        XCTAssertEqual(CountdownFormatter.string(for: 3720), "1h 2m")
    }

    func testRoundsUpSoATickingCountdownNeverShowsZeroEarly() {
        XCTAssertEqual(CountdownFormatter.string(for: 0.4), "1s")
    }

    func testShowsZeroOnlyWhenTimeIsActuallyUp() {
        XCTAssertEqual(CountdownFormatter.string(for: 0), "0s")
    }

    func testTreatsNegativeTimeAsUp() {
        XCTAssertEqual(CountdownFormatter.string(for: -10), "0s")
    }

    // MARK: - Grace period labels

    func testLabelsGracePeriodsInWholeMinutes() {
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 60), "1 minute")
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 300), "5 minutes")
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 1800), "30 minutes")
    }

    func testLabelsWholeHoursAsHours() {
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 3600), "1 hour")
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 7200), "2 hours")
    }

    func testLabelsAGracePeriodThatIsNotAWholeNumberOfMinutes() {
        XCTAssertEqual(CountdownFormatter.gracePeriodLabel(for: 90), "1m 30s")
    }
}

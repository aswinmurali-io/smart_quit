// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class AccessibilityWindowCounterTests: XCTestCase {
    /// Builds a counter over a canned list of window subroles.
    private func counter(
        returning subroles: [AccessibilityWindowCounter.WindowSubrole]?
    ) -> AccessibilityWindowCounter {
        AccessibilityWindowCounter { _ in subroles }
    }

    func testCountsStandardWindows() {
        let subject = counter(returning: [.named("AXStandardWindow"), .named("AXStandardWindow")])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 2)
    }

    func testIgnoresSheetsPopoversAndPanels() {
        let subject = counter(returning: [
            .named("AXStandardWindow"), .named("AXSheet"),
            .named("AXSystemDialog"), .named("AXUnknown"),
        ])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 1)
    }

    func testIgnoresWindowsWithNoSubrole() {
        let subject = counter(returning: [.absent, .absent])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 0)
    }

    func testReportsZeroForAnAppWithNoWindows() {
        let subject = counter(returning: [])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 0)
    }

    func testReportsUnknownWhenTheAppCannotBeQueried() {
        let subject = counter(returning: nil)

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }
}

// MARK: - A window that cannot be classified

extension AccessibilityWindowCounterTests {
    /// A window we could not ask is not a window we know to be uninteresting.
    /// Counting it as "not standard" hides a real window and reports a
    /// confident zero, which puts a working app on the clock.
    func testAWindowWhoseSubroleCannotBeReadMakesTheCountUnknown() {
        let subject = counter(returning: [.unknown])

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }

    /// The count is unknown even when another window did answer: the app has at
    /// least one window we cannot account for, so its total is not knowable.
    func testOneUnreadableWindowMakesTheWholeCountUnknown() {
        let subject = counter(returning: [.named("AXStandardWindow"), .unknown])

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }

    /// Reproduces a locked screen. The app answers with its windows, but every
    /// window reports `attributeUnsupported` for its subrole, so all of them
    /// are unclassifiable. This used to count as zero and quit the user's
    /// session out from under the lock screen.
    func testALockedScreenLeavesTheCountUnknownRatherThanZero() {
        let subject = counter(returning: [.unknown, .unknown])

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }

    /// A window with no subrole is still a confident answer, so an app whose
    /// only window is one of those stays at zero. Finder's desktop window does
    /// this on every sweep, so this must not become unknown.
    func testAWindowWithNoSubroleIsStillACertainAnswer() {
        let subject = counter(returning: [.absent, .named("AXSheet")])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 0)
    }
}

// MARK: - Interpreting Accessibility errors

extension AccessibilityWindowCounterTests {
    func testASuccessfulQueryYieldsAValue() {
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .success), .value)
    }

    /// The app answered and simply has no windows attribute value.
    func testNoValueMeansTheAppHasNoWindows() {
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .noValue), .none)
    }

    /// "This element has no such attribute" is not "this app has no windows".
    /// Treating it as zero would make the app a quit candidate. This is the
    /// error a locked screen returns for every window's subrole.
    func testAnUnsupportedAttributeIsUnknownRatherThanZero() {
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .attributeUnsupported), .unknown)
    }

    func testAnUnresponsiveAppIsUnknown() {
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .cannotComplete), .unknown)
    }

    func testMissingPermissionIsUnknown() {
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .apiDisabled), .unknown)
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .notImplemented), .unknown)
        XCTAssertEqual(AccessibilityWindowCounter.outcome(for: .invalidUIElement), .unknown)
    }
}

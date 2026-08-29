// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class SpaceAwareWindowCounterTests: XCTestCase {
    /// Builds a counter over a fixed active-Space count and Space lookup.
    private func counter(
        onActiveSpace: Int?,
        elsewhere: [pid_t: Int]
    ) -> SpaceAwareWindowCounter {
        let subject = SpaceAwareWindowCounter(
            counter: StubWindowCounter(count: onActiveSpace),
            lookup: StubSpaceWindowLookup(counts: elsewhere)
        )
        subject.prepareForSweep()
        return subject
    }

    /// The failure this type exists for: every window on another desktop, and
    /// Accessibility answering a confident zero.
    func testAnAppWhoseWindowsAreAllOnAnotherSpaceIsNotWindowless() {
        let subject = counter(onActiveSpace: 0, elsewhere: [1: 3])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 3)
    }

    func testAddsWindowsElsewhereToThoseInFront() {
        let subject = counter(onActiveSpace: 2, elsewhere: [1: 1])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 3)
    }

    func testAnAppWithNoWindowsAnywhereIsStillWindowless() {
        let subject = counter(onActiveSpace: 0, elsewhere: [:])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 0)
    }

    func testLeavesAnAppWithNoWindowsElsewhereUntouched() {
        let subject = counter(onActiveSpace: 2, elsewhere: [99: 5])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 2)
    }

    /// Unknown must survive the addition. Turning "we could not ask" into a
    /// number is what makes an app a quit candidate.
    func testAnAppThatCouldNotBeQueriedStaysUnknown() {
        let subject = counter(onActiveSpace: nil, elsewhere: [1: 3])

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }

    func testAnAppThatCouldNotBeQueriedStaysUnknownWithNoWindowsElsewhere() {
        let subject = counter(onActiveSpace: nil, elsewhere: [:])

        XCTAssertNil(subject.standardWindowCount(pid: 1))
    }

    /// The window list is one snapshot of the whole system, so it is read once
    /// per sweep however many apps are counted against it.
    func testTakesOneSnapshotPerSweepRatherThanOnePerApp() {
        let lookup = StubSpaceWindowLookup(counts: [:])
        let subject = SpaceAwareWindowCounter(counter: StubWindowCounter(count: 0), lookup: lookup)

        subject.prepareForSweep()
        _ = subject.standardWindowCount(pid: 1)
        _ = subject.standardWindowCount(pid: 2)
        _ = subject.standardWindowCount(pid: 3)

        XCTAssertEqual(lookup.readCount, 1)
    }

    func testForwardsPreparationToTheCounterItWraps() {
        let inner = StubWindowCounter(count: 0)
        let subject = SpaceAwareWindowCounter(counter: inner, lookup: StubSpaceWindowLookup(counts: [:]))

        subject.prepareForSweep()

        XCTAssertEqual(inner.prepareCount, 1)
    }
}

// MARK: - Stubs

/// A counter that reports the same answer for every process.
private final class StubWindowCounter: WindowCounting {
    let count: Int?
    private(set) var prepareCount = 0

    init(count: Int?) { self.count = count }

    func prepareForSweep() { prepareCount += 1 }

    func standardWindowCount(pid: pid_t) -> Int? { count }
}

/// A Space lookup that records how often it was consulted.
private final class StubSpaceWindowLookup: SpaceWindowLookup {
    let counts: [pid_t: Int]
    private(set) var readCount = 0

    init(counts: [pid_t: Int]) { self.counts = counts }

    func windowCountsOnInactiveSpaces() -> [pid_t: Int] {
        readCount += 1
        return counts
    }
}

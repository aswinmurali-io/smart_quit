import XCTest
@testable import LingererCore

final class AccessibilityWindowCounterTests: XCTestCase {
    /// Builds a counter over a canned list of window subroles.
    private func counter(returning subroles: [String?]?) -> AccessibilityWindowCounter {
        AccessibilityWindowCounter { _ in subroles }
    }

    func testCountsStandardWindows() {
        let subject = counter(returning: ["AXStandardWindow", "AXStandardWindow"])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 2)
    }

    func testIgnoresSheetsPopoversAndPanels() {
        let subject = counter(returning: ["AXStandardWindow", "AXSheet", "AXSystemDialog", "AXUnknown"])

        XCTAssertEqual(subject.standardWindowCount(pid: 1), 1)
    }

    func testIgnoresWindowsWithNoSubrole() {
        let subject = counter(returning: [nil, nil])

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

// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XCTest
@testable import SmartQuitCore

final class SpaceWindowLookupTests: XCTestCase {
    /// One `CGWindowList` entry, stated in the terms the lookup actually reads.
    private func window(id: Int, pid: pid_t, layer: Int = 0) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
        ]
    }

    /// Builds a lookup over a canned window list and Space map.
    private func lookup(
        windows: [[String: Any]],
        activeSpaces: Set<Int>,
        spacesByWindow: [Int: Set<Int>]
    ) -> SkyLightSpaceWindowLookup {
        SkyLightSpaceWindowLookup(
            readWindowList: { windows },
            readActiveSpaces: { activeSpaces },
            readWindowSpaces: { spacesByWindow[$0] ?? [] }
        )
    }

    func testCountsWindowsOnAnInactiveSpace() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7), window(id: 11, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [2], 11: [3]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 2])
    }

    /// These are already in the Accessibility count; adding them would double it.
    func testIgnoresWindowsOnTheSpaceTheUserIsLookingAt() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [1]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    /// A window shown on every Space is on the active one too.
    func testIgnoresAWindowPresentOnTheActiveSpaceAmongOthers() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [1, 2, 3]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    /// The whole reason Space membership is consulted rather than window
    /// geometry: shadows, icon buffers, and the remains of closed windows sit
    /// at layer 0 and look like windows, but belong to no Space.
    func testIgnoresSurfacesThatBelongToNoSpace() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7), window(id: 11, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: []]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    /// Menus, the Dock, status items, and the desktop are not at layer 0.
    func testIgnoresWindowsOutsideTheNormalLayer() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7, layer: 103), window(id: 11, pid: 7, layer: 1000)],
            activeSpaces: [1],
            spacesByWindow: [10: [2], 11: [2]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    func testCountsSeparatelyPerApplication() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7), window(id: 11, pid: 8), window(id: 12, pid: 8)],
            activeSpaces: [1],
            spacesByWindow: [10: [2], 11: [2], 12: [3]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 1, 8: 2])
    }

    /// Each display shows its own Space, so a window is only elsewhere when it
    /// is on none of them.
    func testTreatsEveryDisplaysCurrentSpaceAsActive() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7), window(id: 11, pid: 7)],
            activeSpaces: [1, 4],
            spacesByWindow: [10: [4], 11: [5]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 1])
    }

    /// Without SkyLight there is no notion of an active Space, and reporting
    /// every window as elsewhere would stop Smart Quit quitting anything.
    func testReportsNothingWhenNoActiveSpaceIsKnown() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7)],
            activeSpaces: [],
            spacesByWindow: [10: [2]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    /// Entries without the keys the lookup needs are skipped, not crashed on.
    func testIgnoresMalformedWindowEntries() {
        let subject = lookup(
            windows: [[:], [kCGWindowLayer as String: 0], window(id: 10, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [2]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 1])
    }
}

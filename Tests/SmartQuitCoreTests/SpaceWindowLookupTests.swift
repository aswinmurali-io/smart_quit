// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XCTest
@testable import SmartQuitCore

final class SpaceWindowLookupTests: XCTestCase {
    /// One `CGWindowList` entry, stated in the terms the lookup actually reads.
    private func window(id: CGWindowID, pid: pid_t, layer: Int = 0) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
        ]
    }

    /// Builds a lookup over a canned window list, Space map, and ordered-in set.
    ///
    /// Windows are ordered in unless `orderedOut` says otherwise, since that is
    /// the ordinary case and the exception is what each test is about.
    private func lookup(
        windows: [[String: Any]],
        activeSpaces: Set<Int>,
        spacesByWindow: [CGWindowID: Set<Int>],
        orderedOut: Set<CGWindowID> = []
    ) -> SkyLightSpaceWindowLookup {
        SkyLightSpaceWindowLookup(
            readWindowList: { windows },
            readActiveSpaces: { activeSpaces },
            readWindowSpaces: { spacesByWindow[$0] ?? [] },
            readWindowOrderedIn: { !orderedOut.contains($0) }
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

    /// Shadows and icon buffers sit at layer 0 and look like windows by size,
    /// but the window server puts them on no Space at all.
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

    /// The defect that Space membership alone does not catch. When a window is
    /// closed the window server keeps its surface, on the Space that window sat
    /// on — so an app the user emptied on desktop 1 looks, from desktop 2, as
    /// though it still has a window there. Left uncaught, that app can never be
    /// quit again.
    func testIgnoresTheSurfaceOfAClosedWindowOnAnotherSpace() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [2]],
            orderedOut: [10]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [:])
    }

    /// The case this whole type exists for, and the one measured on a real
    /// second desktop: a live window, on a Space the user is not looking at,
    /// which Accessibility reports as not existing.
    func testCountsALiveWindowParkedOnAnotherDesktop() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [2]]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 1])
    }

    /// One app can own both at once, and only the live one is a window.
    func testSeparatesALiveWindowFromADeadSurfaceOwnedByTheSameApp() {
        let subject = lookup(
            windows: [window(id: 10, pid: 7), window(id: 11, pid: 7)],
            activeSpaces: [1],
            spacesByWindow: [10: [2], 11: [2]],
            orderedOut: [11]
        )

        XCTAssertEqual(subject.windowCountsOnInactiveSpaces(), [7: 1])
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

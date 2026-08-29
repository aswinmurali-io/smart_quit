// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Adds the windows an app has on other Mission Control Spaces to the
/// Accessibility count, which only ever sees the Space in front of the user.
///
/// `AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)` enumerates the
/// active Space alone. For an app whose windows are all on another desktop it
/// does not fail — it succeeds and returns an empty array, so the count is a
/// confident `0` rather than the `nil` that would leave the app alone. Without
/// this, moving a window to a second desktop and going back to the first is
/// enough to have the app quit out from under it.
///
/// The Accessibility count stays authoritative for the Space it can see; the
/// Space lookup only ever adds to it. That keeps the direction of any error
/// safe: a surface wrongly taken for a window delays a quit, it never causes
/// one.
///
/// - Important: Like the counter it wraps, this is used from the sweep's
///   counting queue and from nowhere else. ``prepareForSweep()`` and
///   ``standardWindowCount(pid:)`` are not synchronised with each other.
public final class SpaceAwareWindowCounter: WindowCounting {
    private let counter: WindowCounting
    private let lookup: SpaceWindowLookup

    /// Windows on inactive Spaces as of the current sweep, by owning process.
    ///
    /// Read once per sweep rather than once per app: the window list is a
    /// single snapshot of the whole system, and asking for it again for every
    /// application would be both slower and inconsistent.
    private var windowsElsewhere: [pid_t: Int] = [:]

    public init(
        counter: WindowCounting = AccessibilityWindowCounter(),
        lookup: SpaceWindowLookup = SkyLightSpaceWindowLookup()
    ) {
        self.counter = counter
        self.lookup = lookup
    }

    public func prepareForSweep() {
        counter.prepareForSweep()
        windowsElsewhere = lookup.windowCountsOnInactiveSpaces()
    }

    public func standardWindowCount(pid: pid_t) -> Int? {
        // An app we could not query is unknown wherever its windows are.
        // Answering with the Space count alone would turn "we cannot tell"
        // into a number, which is the mistake this codebase exists to avoid.
        guard let onActiveSpace = counter.standardWindowCount(pid: pid) else { return nil }
        return onActiveSpace + (windowsElsewhere[pid] ?? 0)
    }
}

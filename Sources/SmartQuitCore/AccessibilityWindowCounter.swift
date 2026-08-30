// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import ApplicationServices
import Foundation

/// Counts windows through the Accessibility API.
///
/// The Accessibility API is used in preference to `CGWindowList` because the
/// latter reports off-screen surfaces and helper windows that no user would
/// call a window, which produces false positives.
///
/// Minimized and hidden windows remain in an app's `AXWindows`, so they
/// correctly continue to count as windows.
public final class AccessibilityWindowCounter: WindowCounting {
    /// How a single window answered when asked for its subrole.
    ///
    /// The third case is the point of this type. A window whose subrole cannot
    /// be read is not the same as a window that has none: the first says we
    /// could not classify it, the second says we classified it and it is not a
    /// document window. Collapsing the two makes a real window vanish from the
    /// count, which is exactly what a locked screen used to do.
    enum WindowSubrole: Equatable {
        /// The window answered with this subrole.
        case named(String)
        /// The window answered, and has no subrole.
        case absent
        /// The window could not be asked.
        case unknown
    }

    /// Reads the subrole of each of an app's windows.
    ///
    /// Returns `nil` if the application could not be queried at all.
    typealias SubroleReader = (pid_t) -> [WindowSubrole]?

    /// What an Accessibility error means for reading an attribute.
    ///
    /// This applies to any attribute read, not only the windows list: the same
    /// three-way distinction decides whether a per-window subrole was answered,
    /// answered as absent, or could not be determined.
    enum Outcome: Equatable {
        /// The query succeeded; read the attribute out of the value.
        case value
        /// The element answered, and has no value for this attribute.
        case none
        /// The attribute could not be determined.
        case unknown
    }

    /// How long to wait on an unresponsive app before giving up on it.
    ///
    /// Accessibility calls are synchronous, so without a short timeout a single
    /// hung application would stall the whole sweep.
    public static let messagingTimeout: Float = 0.5

    private let readSubroles: SubroleReader

    init(readSubroles: @escaping SubroleReader) {
        self.readSubroles = readSubroles
    }

    public convenience init() {
        // The timeout must be set on the system-wide element to apply to this
        // process as a whole. Setting it on an application element covers only
        // messages to that element — not to the window elements it returns, so
        // the per-window subrole queries would still wait out the 6s default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
        self.init(readSubroles: Self.readSubrolesViaAccessibility)
    }

    /// Maps an Accessibility error onto what it means for a value we asked for.
    ///
    /// Only `noValue` means "there is none". Everything else that is not a
    /// success is unknown — in particular `attributeUnsupported`, which says the
    /// element has no such attribute, not that the answer is empty. Reporting
    /// zero there would make the app a quit candidate.
    static func outcome(for result: AXError) -> Outcome {
        switch result {
        case .success: return .value
        case .noValue: return .none
        default: return .unknown
        }
    }

    public func standardWindowCount(pid: pid_t) -> Int? {
        guard let subroles = readSubroles(pid) else { return nil }

        // A window we could not classify makes the whole count unknown. The app
        // told us it has this window, so leaving it out would report a number
        // lower than the truth — and for an app whose windows are all
        // unreadable, that number is zero, which starts the clock on an app the
        // user is working in. A locked screen does exactly that: the windows
        // list still answers, but every subrole comes back
        // `attributeUnsupported` until the screen is unlocked.
        guard !subroles.contains(.unknown) else { return nil }

        return subroles.filter { $0 == .named(kAXStandardWindowSubrole as String) }.count
    }

    // MARK: - Accessibility

    private static func readSubrolesViaAccessibility(pid: pid_t) -> [WindowSubrole]? {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)

        switch outcome(for: result) {
        case .value:
            guard let windows = value as? [AXUIElement] else { return nil }
            let subroles = windows.map(subrole(of:))

            // Symmetric with the app-level failure below, and for a worse
            // problem. `attributeUnsupported` is a permanent property of an
            // element as readily as it is a locked screen, so a window from a
            // toolkit that never vends `AXSubrole` holds its app at an unknown
            // count for as long as that window is open: never quit, and absent
            // from the apps-with-windows list, with nothing on screen to say
            // why. Silent, this would be undiagnosable from a user's logs.
            let unreadable = subroles.filter { $0 == .unknown }.count
            if unreadable > 0 {
                Log.windows.debug(
                    """
                    pid \(pid): \(unreadable) of \(windows.count) window(s) \
                    would not report a subrole — count unknown
                    """
                )
            }
            return subroles
        case .none:
            return []
        case .unknown:
            Log.windows.debug("Window query for pid \(pid) failed: \(result.rawValue)")
            return nil
        }
    }

    private static func subrole(of window: AXUIElement) -> WindowSubrole {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)

        switch outcome(for: result) {
        case .value:
            guard let name = value as? String else { return .unknown }
            return .named(name)
        case .none:
            return .absent
        case .unknown:
            return .unknown
        }
    }
}

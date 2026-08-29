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
    /// Reads the subrole of each of an app's windows.
    ///
    /// Returns `nil` if the application could not be queried at all. Individual
    /// elements are `nil` when a window has no subrole.
    typealias SubroleReader = (pid_t) -> [String?]?

    /// What an Accessibility error means for counting windows.
    enum Outcome: Equatable {
        /// The query succeeded; read the windows out of the value.
        case windows
        /// The app answered and has no windows.
        case none
        /// The count could not be determined.
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

    /// Maps an Accessibility error onto what it means for a window count.
    ///
    /// Only `noValue` means "no windows". Everything else that is not a success
    /// is unknown — in particular `attributeUnsupported`, which says the element
    /// has no such attribute, not that the app has no windows. Reporting zero
    /// there would make the app a quit candidate.
    static func outcome(for result: AXError) -> Outcome {
        switch result {
        case .success: return .windows
        case .noValue: return .none
        default: return .unknown
        }
    }

    public func standardWindowCount(pid: pid_t) -> Int? {
        guard let subroles = readSubroles(pid) else { return nil }
        return subroles.filter { $0 == kAXStandardWindowSubrole as String }.count
    }

    // MARK: - Accessibility

    private static func readSubrolesViaAccessibility(pid: pid_t) -> [String?]? {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)

        switch outcome(for: result) {
        case .windows:
            guard let windows = value as? [AXUIElement] else { return nil }
            return windows.map(subrole(of:))
        case .none:
            return []
        case .unknown:
            Log.windows.debug("Window query for pid \(pid) failed: \(result.rawValue)")
            return nil
        }
    }

    private static func subrole(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}

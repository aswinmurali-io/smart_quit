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
        self.init(readSubroles: Self.readSubrolesViaAccessibility)
    }

    public func standardWindowCount(pid: pid_t) -> Int? {
        guard let subroles = readSubroles(pid) else { return nil }
        return subroles.filter { $0 == kAXStandardWindowSubrole as String }.count
    }

    // MARK: - Accessibility

    private static func readSubrolesViaAccessibility(pid: pid_t) -> [String?]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)

        switch result {
        case .success:
            guard let windows = value as? [AXUIElement] else { return nil }
            return windows.map(subrole(of:))
        case .noValue, .attributeUnsupported:
            // The app is reachable and simply has no windows attribute.
            return []
        default:
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

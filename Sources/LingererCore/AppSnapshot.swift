import Foundation

/// A single application as observed during one sweep.
///
/// This is a value type with no AppKit dependency so the decision logic in
/// ``LingerEngine`` can be exercised without a running window server.
public struct AppSnapshot: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String
    public let isFrontmost: Bool

    /// Number of standard windows the app has open.
    ///
    /// `nil` means the window count could not be determined — the Accessibility
    /// query failed or timed out. It is deliberately distinct from `0`: an app
    /// we could not inspect is never a candidate for quitting.
    public let windowCount: Int?

    public init(pid: pid_t, bundleID: String, name: String, isFrontmost: Bool, windowCount: Int?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isFrontmost = isFrontmost
        self.windowCount = windowCount
    }
}

extension AppSnapshot {
    /// Combines a running app with the number of windows it was found to have.
    public init(_ app: RunningApp, windowCount: Int?) {
        self.init(
            pid: app.pid,
            bundleID: app.bundleID,
            name: app.name,
            isFrontmost: app.isFrontmost,
            windowCount: windowCount
        )
    }
}

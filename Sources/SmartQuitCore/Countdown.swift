import Foundation

/// An app currently on the clock, for display in the menu.
public struct Countdown: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    /// Seconds until this app is quit. Never negative.
    public let remaining: TimeInterval

    public init(pid: pid_t, bundleID: String, name: String, remaining: TimeInterval) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.remaining = remaining
    }
}

import Foundation

/// An app currently on the clock, for display in the menu.
public struct Countdown: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    /// Seconds until this app is quit. Never negative.
    ///
    /// Frozen while ``isPaused`` — it neither counts down between sweeps nor
    /// advances across them.
    public let remaining: TimeInterval

    /// Whether the clock is held because the app is playing audio.
    public let isPaused: Bool

    public init(
        pid: pid_t,
        bundleID: String,
        name: String,
        remaining: TimeInterval,
        isPaused: Bool = false
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.remaining = remaining
        self.isPaused = isPaused
    }
}

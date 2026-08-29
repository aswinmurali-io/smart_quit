import Foundation
import os

/// Logging for the app's decisions.
///
/// Every state transition is recorded here, so `log stream --predicate
/// 'subsystem == "com.smartquit.SmartQuit"'` gives a complete account of why
/// any application was or was not quit.
public enum Log {
    public static let subsystem = "com.smartquit.SmartQuit"

    /// State transitions in the decision engine.
    public static let engine = Logger(subsystem: subsystem, category: "engine")

    /// Accessibility window counting.
    public static let windows = Logger(subsystem: subsystem, category: "windows")

    /// Menu bar and permission flows.
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Which processes are playing audio, and why a query failed.
    public static let audio = Logger(subsystem: subsystem, category: "audio")
}

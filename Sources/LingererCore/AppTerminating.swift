import Foundation

/// Quitting an application, and checking whether it actually went away.
public protocol AppTerminating: AnyObject {
    /// Requests a graceful quit. Returns whether the request was accepted.
    func terminate(pid: pid_t) -> Bool

    /// Whether the process is still alive.
    func isRunning(pid: pid_t) -> Bool
}

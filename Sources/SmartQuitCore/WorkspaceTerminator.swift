// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// Quits applications via `NSRunningApplication`.
public final class WorkspaceTerminator: AppTerminating {
    public init() {}

    /// Requests a graceful quit.
    ///
    /// This is deliberately `terminate()` and never `terminate(force:)`: the
    /// graceful path lets an app present its unsaved-changes dialog and refuse,
    /// which is the behaviour we want. Nothing here should ever cost work.
    public func terminate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.terminate()
    }

    public func isRunning(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }
}

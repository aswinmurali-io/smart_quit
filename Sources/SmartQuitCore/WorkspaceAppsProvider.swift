import AppKit
import Foundation

/// Lists running applications via `NSWorkspace`.
public final class WorkspaceAppsProvider: RunningAppsProviding {
    public init() {}

    public func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    public func regularApps() -> [RunningApp] {
        let workspace = NSWorkspace.shared
        let frontmost = frontmostPID()

        return workspace.runningApplications.compactMap { app in
            // Only Dock-visible apps. Accessory and prohibited policies cover
            // menu bar utilities and background agents, which have no windows
            // by design and must never be quit.
            guard app.activationPolicy == .regular else { return nil }
            guard let bundleID = app.bundleIdentifier else { return nil }

            return RunningApp(
                pid: app.processIdentifier,
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                isFrontmost: app.processIdentifier == frontmost
            )
        }
    }
}

import Foundation

/// An application as the workspace reports it, before its windows are counted.
public struct RunningApp: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String
    public let isFrontmost: Bool

    public init(pid: pid_t, bundleID: String, name: String, isFrontmost: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isFrontmost = isFrontmost
    }
}

/// Lists the applications eligible for consideration.
public protocol RunningAppsProviding: AnyObject {
    /// Apps with a regular activation policy — the ones that appear in the Dock.
    ///
    /// Accessory and prohibited apps (menu bar utilities, background agents)
    /// and apps without a bundle identifier are excluded.
    func regularApps() -> [RunningApp]
}

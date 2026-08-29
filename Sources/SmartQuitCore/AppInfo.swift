import Foundation

/// What the app knows about itself.
public enum AppInfo {
    /// Where releases are published.
    ///
    /// There is no update mechanism in the app: "Check for Updates…" opens this
    /// page and leaves the rest to the person. A menu bar utility that quits
    /// other applications is the last thing that should also be downloading and
    /// replacing itself in the background.
    public static let releasesURL = URL(
        string: "https://github.com/aswinmurali-io/smart_quit/releases"
    )

    /// The version from the bundle's `Info.plist`, or `nil` if it cannot be read.
    ///
    /// `nil` outside a real app bundle — under `xctest` `Bundle.main` is the
    /// test runner. Callers omit the version rather than showing a placeholder.
    public static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

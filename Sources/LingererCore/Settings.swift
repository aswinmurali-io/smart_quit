import Foundation

/// User preferences, backed by `UserDefaults`.
public final class Settings: SettingsProviding {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let globalGracePeriod = "globalGracePeriod"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let gracePeriodOverrides = "gracePeriodOverrides"
        static let hasSeededExclusions = "hasSeededExclusions"
    }

    /// Grace period offered in the menu, in seconds.
    public static let gracePeriodPresets: [TimeInterval] = [60, 120, 300, 600, 1800]

    public static let defaultGracePeriod: TimeInterval = 300

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.globalGracePeriod: Self.defaultGracePeriod,
        ])
        seedExclusionsIfNeeded()
    }

    /// Populates the exclusion list on first run only, so that an app the user
    /// has deliberately removed does not come back on the next launch.
    private func seedExclusionsIfNeeded() {
        guard !defaults.bool(forKey: Key.hasSeededExclusions) else { return }
        defaults.set(Array(DefaultExclusions.bundleIDs), forKey: Key.excludedBundleIDs)
        defaults.set(true, forKey: Key.hasSeededExclusions)
    }

    // MARK: - Global

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    public var globalGracePeriod: TimeInterval {
        get { defaults.double(forKey: Key.globalGracePeriod) }
        set {
            guard newValue > 0 else { return }
            defaults.set(newValue, forKey: Key.globalGracePeriod)
        }
    }

    // MARK: - Exclusions

    public var excludedBundleIDs: Set<String> {
        Set(defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [])
    }

    public func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    public func setExcluded(_ excluded: Bool, bundleID: String) {
        var ids = excludedBundleIDs
        if excluded {
            ids.insert(bundleID)
        } else {
            ids.remove(bundleID)
        }
        defaults.set(Array(ids), forKey: Key.excludedBundleIDs)
    }

    // MARK: - Per-app grace periods

    private var overrides: [String: TimeInterval] {
        get { defaults.dictionary(forKey: Key.gracePeriodOverrides) as? [String: TimeInterval] ?? [:] }
        set { defaults.set(newValue, forKey: Key.gracePeriodOverrides) }
    }

    public func gracePeriod(forBundleID bundleID: String) -> TimeInterval {
        overrides[bundleID] ?? globalGracePeriod
    }

    /// The app's own grace period, or `nil` when it follows the global setting.
    public func gracePeriodOverride(forBundleID bundleID: String) -> TimeInterval? {
        overrides[bundleID]
    }

    /// Sets an app-specific grace period. Passing `nil` restores the global one.
    public func setGracePeriod(_ period: TimeInterval?, forBundleID bundleID: String) {
        var current = overrides
        if let period, period > 0 {
            current[bundleID] = period
        } else {
            current[bundleID] = nil
        }
        overrides = current
    }
}

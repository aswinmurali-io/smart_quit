// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// User preferences, backed by `UserDefaults`.
public final class Settings: SettingsProviding {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let globalGracePeriod = "globalGracePeriod"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let gracePeriodOverrides = "gracePeriodOverrides"
        static let hasSeededExclusions = "hasSeededExclusions"
        static let pausesWhilePlayingAudio = "pausesWhilePlayingAudio"
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
            Key.pausesWhilePlayingAudio: true,
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
        // Clamped on read as well as write: a value written directly to the
        // defaults domain bypasses the setter, and a non-positive grace period
        // would make every windowless app due on its first sweep.
        get {
            let stored = defaults.double(forKey: Key.globalGracePeriod)
            return stored > 0 ? stored : Self.defaultGracePeriod
        }
        set {
            guard newValue > 0 else { return }
            defaults.set(newValue, forKey: Key.globalGracePeriod)
        }
    }

    /// Whether an app playing audio has its clock held.
    public var pausesWhilePlayingAudio: Bool {
        get { defaults.bool(forKey: Key.pausesWhilePlayingAudio) }
        set { defaults.set(newValue, forKey: Key.pausesWhilePlayingAudio) }
    }

    // MARK: - Exclusions

    public var excludedBundleIDs: Set<String> {
        // compactMap rather than stringArray(forKey:), which returns nil for
        // the whole array if any element is not a string. Losing every
        // exclusion to one bad entry would make protected apps quittable.
        Set((defaults.array(forKey: Key.excludedBundleIDs) ?? []).compactMap { $0 as? String })
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
        // Per value rather than all-or-nothing, for the same reason as above.
        get {
            (defaults.dictionary(forKey: Key.gracePeriodOverrides) ?? [:])
                .compactMapValues { ($0 as? NSNumber)?.doubleValue }
                .filter { $0.value > 0 }
        }
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

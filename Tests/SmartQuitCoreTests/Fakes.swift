// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
@testable import SmartQuitCore

/// Settings under full test control. Mirrors the real UserDefaults-backed type.
final class FakeSettings: SettingsProviding {
    var isEnabled = true
    var globalGracePeriod: TimeInterval = 300
    var perAppGracePeriods: [String: TimeInterval] = [:]
    var excludedBundleIDs: Set<String> = []
    var pausesWhilePlayingAudio = true

    func gracePeriod(forBundleID bundleID: String) -> TimeInterval {
        perAppGracePeriods[bundleID] ?? globalGracePeriod
    }

    func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }
}

/// Records termination requests instead of quitting anything.
final class SpyTerminator: AppTerminating {
    private(set) var terminated: [pid_t] = []
    /// PIDs that refuse to die, to exercise the verification path.
    var stillRunningAfterTerminate: Set<pid_t> = []
    /// Value returned by `terminate(pid:)`.
    var terminateResult = true

    func terminate(pid: pid_t) -> Bool {
        terminated.append(pid)
        return terminateResult
    }

    func isRunning(pid: pid_t) -> Bool {
        stillRunningAfterTerminate.contains(pid)
    }
}

extension AppSnapshot {
    /// Convenience builder so tests only state the field under test.
    static func make(
        pid: pid_t = 1,
        bundleID: String = "com.example.App",
        name: String = "App",
        isFrontmost: Bool = false,
        windowCount: Int? = 0,
        isPlayingAudio: Bool = false
    ) -> AppSnapshot {
        AppSnapshot(
            pid: pid,
            bundleID: bundleID,
            name: name,
            isFrontmost: isFrontmost,
            windowCount: windowCount,
            isPlayingAudio: isPlayingAudio
        )
    }
}

/// Window counts under full test control.
final class FakeWindowCounter: WindowCounting {
    var countsByPID: [pid_t: Int?] = [:]
    private(set) var queried: [pid_t] = []
    /// How many times the sweep announced itself.
    private(set) var prepareCount = 0
    /// Whether preparation happened before the first app was counted. A counter
    /// that snapshots the system in `prepareForSweep` answers from stale state
    /// — or from none at all — if this is ever false.
    private(set) var preparedBeforeFirstQuery = false
    /// Runs during the count, to simulate the world changing mid-sweep.
    var onQuery: ((pid_t) -> Void)?

    func prepareForSweep() {
        if queried.isEmpty { preparedBeforeFirstQuery = true }
        prepareCount += 1
    }

    func standardWindowCount(pid: pid_t) -> Int? {
        queried.append(pid)
        onQuery?(pid)
        return countsByPID[pid] ?? 0
    }
}

/// A canned list of running applications.
final class FakeAppsProvider: RunningAppsProviding {
    var apps: [RunningApp] = []
    var frontmost: pid_t?

    func regularApps() -> [RunningApp] { apps }
    func frontmostPID() -> pid_t? { frontmost }
}

extension RunningApp {
    static func make(
        pid: pid_t = 1,
        bundleID: String = "com.example.App",
        name: String = "App",
        isFrontmost: Bool = false
    ) -> RunningApp {
        RunningApp(pid: pid, bundleID: bundleID, name: name, isFrontmost: isFrontmost)
    }
}

/// Audio activity under full test control.
final class FakeAudioActivityDetector: AudioActivityDetecting {
    var playing: Set<pid_t> = []

    func pidsPlayingAudio() -> Set<pid_t> { playing }
}

/// A canned process tree. A pid with no entry has no parent.
final class FakeProcessAncestry: ProcessAncestry {
    var parents: [pid_t: pid_t] = [:]

    func parent(of pid: pid_t) -> pid_t? { parents[pid] }
}

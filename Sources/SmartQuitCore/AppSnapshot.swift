// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// A single application as observed during one sweep.
///
/// This is a value type with no AppKit dependency so the decision logic in
/// ``QuitEngine`` can be exercised without a running window server.
public struct AppSnapshot: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String
    public let isFrontmost: Bool

    /// Number of standard windows the app has open.
    ///
    /// `nil` means the window count could not be determined — the Accessibility
    /// query failed or timed out. It is deliberately distinct from `0`: an app
    /// we could not inspect is never a candidate for quitting.
    public let windowCount: Int?

    /// Whether the app, or a helper process it owns, is playing audio.
    ///
    /// A windowless app that is playing something is still in use, so its
    /// clock is held rather than allowed to run out.
    public let isPlayingAudio: Bool

    public init(
        pid: pid_t,
        bundleID: String,
        name: String,
        isFrontmost: Bool,
        windowCount: Int?,
        isPlayingAudio: Bool = false
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isFrontmost = isFrontmost
        self.windowCount = windowCount
        self.isPlayingAudio = isPlayingAudio
    }
}

extension AppSnapshot {
    /// A copy with the frontmost flag brought up to date.
    func withFrontmost(_ isFrontmost: Bool) -> AppSnapshot {
        AppSnapshot(
            pid: pid,
            bundleID: bundleID,
            name: name,
            isFrontmost: isFrontmost,
            windowCount: windowCount,
            isPlayingAudio: isPlayingAudio
        )
    }

    /// Combines a running app with what the sweep found out about it.
    public init(_ app: RunningApp, windowCount: Int?, isPlayingAudio: Bool = false) {
        self.init(
            pid: app.pid,
            bundleID: app.bundleID,
            name: app.name,
            isFrontmost: app.isFrontmost,
            windowCount: windowCount,
            isPlayingAudio: isPlayingAudio
        )
    }
}

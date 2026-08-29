// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// An app currently on the clock, for display in the menu.
public struct Countdown: Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    /// Seconds until this app is quit. Never negative.
    ///
    /// Frozen while ``isPaused`` — it neither counts down between sweeps nor
    /// advances across them.
    public let remaining: TimeInterval

    /// Whether the clock is held because the app is playing audio.
    public let isPaused: Bool

    /// Whether this is the app the user is currently in.
    ///
    /// Its clock still runs — it is simply not quit while it is in front, so a
    /// countdown can sit at zero indefinitely without anything being wrong.
    public let isFrontmost: Bool

    public init(
        pid: pid_t,
        bundleID: String,
        name: String,
        remaining: TimeInterval,
        isPaused: Bool = false,
        isFrontmost: Bool = false
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.remaining = remaining
        self.isPaused = isPaused
        self.isFrontmost = isFrontmost
    }
}

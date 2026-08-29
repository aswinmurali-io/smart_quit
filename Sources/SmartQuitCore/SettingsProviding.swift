// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Read access to the user's preferences, as the engine needs them.
public protocol SettingsProviding: AnyObject {
    /// Global pause switch. When false the engine takes no action at all.
    var isEnabled: Bool { get }

    /// Grace period for a specific app, falling back to ``globalGracePeriod``.
    func gracePeriod(forBundleID bundleID: String) -> TimeInterval

    /// Whether the user has opted this app out of automatic quitting.
    func isExcluded(bundleID: String) -> Bool

    /// Whether an app playing audio has its clock held.
    ///
    /// On by default. Off makes audio irrelevant to the decision, which suits
    /// someone who leaves music running all day and wants the windowless rule
    /// applied regardless.
    var pausesWhilePlayingAudio: Bool { get }
}

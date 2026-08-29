// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import ApplicationServices
import AppKit
import Foundation

/// The Accessibility permission that window counting depends on.
public enum AccessibilityPermission {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    /// Whether the app is currently trusted, without prompting.
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Whether the app is trusted, showing the system prompt if it is not.
    ///
    /// The prompt appears once per app signature; afterwards macOS stays quiet
    /// and the user must go to System Settings, which ``openSystemSettings()``
    /// links to directly.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        Log.ui.info("Accessibility permission granted: \(granted)")
        return granted
    }

    /// Opens Privacy & Security → Accessibility.
    public static func openSystemSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

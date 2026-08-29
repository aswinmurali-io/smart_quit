// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SmartQuitCore
import ServiceManagement

/// Login item registration.
///
/// `SMAppService.mainApp` registers the bundle by its path, so this only works
/// for a built, signed `.app` — and reliably only once that app lives somewhere
/// stable such as `/Applications`.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles the login item. Returns the error to report, if it failed.
    static func setEnabled(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.ui.info("Launch at login set to \(enabled)")
            return nil
        } catch {
            Log.ui.error("Launch at login change failed: \(error.localizedDescription)")
            return error
        }
    }
}

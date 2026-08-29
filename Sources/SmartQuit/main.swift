// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

// LSUIElement is set in Info.plist, but the accessory policy is also set here
// so that running the executable directly (outside the app bundle) behaves the
// same way: no Dock icon, no menu bar takeover.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

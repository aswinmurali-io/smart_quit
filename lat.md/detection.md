# Detection

How SmartQuit decides how many windows an app has, and which apps it is willing to consider at all.

## Accessibility over CGWindowList

Window counts come from the Accessibility API, not `CGWindowList`.

`CGWindowList` reports every surface the window server knows about, including
off-screen buffers, shadows, and helper windows belonging to frameworks. An app
with no visible windows routinely still has entries there, so counting them
produces false negatives — SmartQuit would conclude an app still has windows and
never quit it.

`AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)` returns the windows an
app actually vends, which matches what a person would call a window.

See `AccessibilityWindowCounter` in `Sources/SmartQuitCore/AccessibilityWindowCounter.swift`.

## Only standard windows count

A window counts only when its `AXSubrole` is `AXStandardWindow`.

Sheets, popovers, panels, and system dialogs are all windows to the
Accessibility API but none of them represent a document the user is working in.
An app showing only a save sheet is, for our purposes, windowless.

Windows with no subrole at all are not counted.

## Minimized and hidden windows still count

Minimizing a window, or hiding an app with Cmd-H, does not make it windowless.

Both remain in the app's `AXWindows`, so they continue to count without any
special handling. This is deliberate: a minimized window is work in progress,
and quitting the app would be a surprise.

## Unknown is not zero

A window count is `Int?`. `nil` means the count could not be determined.

An Accessibility query fails when the app is unresponsive, when it has not
finished launching, or when SmartQuit's Accessibility permission has been
revoked. Reporting `0` in those cases would make every such app a quit
candidate — a revoked permission would quit the user's entire session.

Only `kAXErrorNoValue` means "no windows". Everything else that is not a success
is unknown, including `kAXErrorAttributeUnsupported`, which says the element has
no such attribute rather than that the app has no windows. Real apps on a normal
desktop — Xcode and TextEdit among them — return `kAXErrorCannotComplete`
persistently, so this distinction is exercised constantly, not just in theory.

`nil` propagates through `AppSnapshot` in `Sources/SmartQuitCore/AppSnapshot.swift`
and is treated by the engine as "leave this app alone".

## Messaging timeout

The counter sets `AXUIElementSetMessagingTimeout` to 0.5 seconds, on the
system-wide element.

Accessibility calls are synchronous. Without a timeout, one hung application
would block the sweep for as long as it stayed hung, and the menu bar item would
stop updating. A short timeout turns that into a `nil` count, which is the safe
answer.

The timeout must be set on the system-wide element to apply process-wide. Apple
documents that setting it on any other element covers that element alone — so
setting it on the application element left every per-window subrole query
waiting out the 6 second system default, which is the opposite of the intent.

## Eligible applications

Only apps whose `NSRunningApplication.activationPolicy` is `.regular` are considered.

`.accessory` and `.prohibited` cover menu bar utilities, background agents, and
helper processes. Those are windowless by design and quitting them would be
wrong. Apps without a bundle identifier are also skipped, since exclusions are
keyed by bundle identifier and an app without one cannot be excluded.

See `WorkspaceAppsProvider` in `Sources/SmartQuitCore/WorkspaceAppsProvider.swift`.

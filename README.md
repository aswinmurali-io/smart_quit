# Lingerer

A macOS menu bar utility that quits apps you've stopped using.

Closing the last window of a Mac app doesn't quit it — the app lingers in the
background, ready for a fast relaunch. That behaviour is genuinely useful, and
also how you end up with thirty windowless apps holding memory at the end of a
workday.

Lingerer keeps the fast-relaunch behaviour and removes the pile-up. When an app
has had zero open windows for longer than a grace period (5 minutes by default),
Lingerer quits it gracefully.

## Behaviour

- **Windowless means windowless.** Minimized and hidden windows still count as
  windows. An app is only a candidate once it genuinely has no standard windows.
- **Graceful only.** Quitting goes through `NSRunningApplication.terminate()`,
  so unsaved-changes dialogs appear and nothing is lost. Lingerer never sends
  `SIGKILL`.
- **The window you reopen cancels the clock.** If a window reappears before the
  grace period elapses, the pending quit is cancelled.
- **Conservative about what it touches.** Only regular (Dock-visible) apps are
  eligible. Finder, the frontmost app, background agents, menu bar utilities and
  anything on your exclude list are never quit.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (Lingerer reads window counts via the Accessibility
  API; it cannot see window contents)

## Licence

Apache License 2.0 — see [LICENSE](LICENSE).

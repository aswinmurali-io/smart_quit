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
- Xcode command line tools (Swift 5.9 or later)
- Accessibility permission (Lingerer reads window counts via the Accessibility
  API; it cannot see window contents)

## Build and run

Lingerer is a Swift package. There is no `.xcodeproj`: the logic lives in a
library target so it can be unit tested, and a script assembles the `.app`
bundle a menu bar app needs.

```bash
./Scripts/build-app.sh
```

That builds `dist/Lingerer.app` and ad-hoc signs it. Install and launch it:

```bash
cp -R dist/Lingerer.app ~/Applications/ && open ~/Applications/Lingerer.app
```

Lingerer has no Dock icon and no window. Look for the hourglass in the menu bar.

### Grant Accessibility permission

On first launch macOS asks for Accessibility permission. Lingerer cannot count
windows without it, and will sit there doing nothing until it is granted.

If you miss the prompt, open **System Settings → Privacy & Security →
Accessibility**, then add and enable Lingerer. The menu's *Open Accessibility
Settings…* item takes you straight there.

Because the app is ad-hoc signed, its signature changes every time you rebuild
it. macOS ties the Accessibility grant to that signature, so after a rebuild you
may need to remove Lingerer from the Accessibility list and add it again.

### Gatekeeper

An ad-hoc signature is not notarised, so double-clicking the app may be blocked
the first time. Right-click `Lingerer.app` → **Open** → **Open**, which records
your consent. Launching from the command line with `open` avoids this entirely.

### Launch at login

The *Launch at login* toggle uses `SMAppService`, which registers the app by its
path. Keep `Lingerer.app` somewhere stable — `~/Applications` or
`/Applications` — or the login item will point at a file that has moved.

## Debug logging

Every state transition is logged. To watch it live:

```bash
log stream --predicate 'subsystem == "dev.aswinmurali.Lingerer"' --level debug
```

To read what already happened:

```bash
log show --predicate 'subsystem == "dev.aswinmurali.Lingerer"' --last 1h --info --debug
```

The `engine` category records apps becoming windowless, timers being cancelled,
quit requests, and quits that were refused.

## Tests

```bash
swift test
```

The decision engine, settings, menu structure and duration formatting are
covered directly. The engine takes time as a parameter, so the timing tests are
exact and instant rather than sleeping.

Window counting is covered at its seams — the subrole filter and the mapping
from `AXError` to "no windows" versus "unknown" — rather than against a live
window server. The sweep's threading is covered for reentrancy and for
re-reading the frontmost app, which is the path that can quit the wrong app.

## Licence

Apache License 2.0 — see [LICENSE](LICENSE).

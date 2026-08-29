# Quitting

The rules that take an app from "has no windows" to "quit", and the state machine that enforces them.

## The windowless clock

An app with zero standard windows starts a clock. When the clock passes the
grace period, the app is quit.

If a window reappears at any point, the clock is discarded. The next windowless
spell starts a fresh clock rather than resuming the old one — a window that came
back is evidence the app is in use.

See `LingerEngine` in `Sources/LingererCore/LingerEngine.swift`.

## State is keyed by pid

Per-app state is keyed by process identifier, not bundle identifier.

An app that quits and relaunches is a new process. Keying by bundle identifier
would let the relaunched app inherit the clock of the process that just died and
be quit again immediately. Keying by pid gives it a fresh start.

`NSWorkspace.didTerminateApplicationNotification` drops state for apps that quit
on their own, and each sweep prunes state for pids that are no longer running.
As a backstop, an entry whose bundle identifier no longer matches the app now
holding that pid is discarded, so a recycled pid cannot inherit a clock, a
per-app grace override, or a name from the process that died.

## Graceful termination only

Quitting goes through `NSRunningApplication.terminate()`. Never `terminate(force:)`.

The graceful path lets an app present its unsaved-changes dialog and refuse to
quit. That refusal is the correct outcome, not a failure to work around: it is
what keeps Lingerer from ever costing the user work.

See `WorkspaceTerminator` in `Sources/LingererCore/WorkspaceTerminator.swift`.

## A refused quit is not retried

An app that survives a quit request is not asked again until it shows a window.

`terminate()` returning `false`, or the app still running ten seconds later, both
move it to a `surrendered` state. Without that state the app would come back up
for consideration on the next sweep and be asked to quit every fifteen seconds
forever — a dialog storm for an app with unsaved work.

Showing a window clears the state and makes the app eligible again.

## The frontmost app is never quit

An app the user is currently looking at is never quit, even once its clock has run out.

Which app is frontmost is re-read on the main queue immediately before the
decision, not taken from the start of the sweep. Counting windows happens on
another queue and takes time; a user who switches to a windowless app during
that gap would otherwise have the app they just activated quit underneath them.

The clock keeps running while the app is frontmost rather than pausing or
resetting. Switching away from a windowless app that has already served its
grace period quits it on the next sweep, which matches the intent: the app has
not been used for the grace period, and the user has just left it.

## Protected and excluded apps

Finder and Lingerer itself are never quit, and neither is anything on the user's exclude list.

Finder has no meaningful windowless state and quitting it degrades the system.
Exclusions are stored by bundle identifier and seeded on first run only, so an
app the user deliberately un-excludes does not come back on the next launch.

See `DefaultExclusions` in `Sources/LingererCore/DefaultExclusions.swift`.

## One sweep, not one timer per app

A single repeating fifteen-second timer sweeps every application.

A timer per app would mean dozens of timers waking the CPU independently. One
sweep also gives a consistent view: every decision in a pass is made against the
same instant and the same list of running apps.

Listing apps and applying decisions happen on the main queue. The Accessibility
window counting between them runs on a utility queue, because those calls are
synchronous and can block. A sweep that overruns the interval is skipped rather
than queued behind the one in flight.

Nothing in the engine or the sweeper is synchronised, so both are main queue
only. The background hop is given no access to the sweeper's state — it works
from values captured before it starts — and the entry points assert the queue
rather than trusting callers.

See `AppSweeper` in `Sources/LingererCore/AppSweeper.swift`.

## Grace periods

The grace period defaults to five minutes and can be set globally or per app.

A per-app override takes precedence over the global value. Overrides are stored
by bundle identifier and survive relaunches. The menu offers 1, 2, 5, 10 and 30
minutes plus a custom value.

See `Settings` in `Sources/LingererCore/Settings.swift`.

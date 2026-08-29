# Quitting

The rules that take an app from "has no windows" to "quit", and the state machine that enforces them.

## The windowless clock

An app with zero standard windows starts a clock. When the clock passes the
grace period, the app is quit.

If a window reappears at any point, the clock is discarded. The next windowless
spell starts a fresh clock rather than resuming the old one — a window that came
back is evidence the app is in use.

See `QuitEngine` in `Sources/SmartQuitCore/QuitEngine.swift`.

## Audio pauses the clock

An app that is playing audio holds its clock where it is, and resumes from there once the sound stops.

Time served is banked rather than measured from a start date, precisely so it
can be held: a windowless app that plays for an hour comes back to the same
remaining time it had when the music started. Pausing beats resetting because
the app has genuinely been idle for that time, and beats excluding because the
protection lapses on its own when the audio does.

An app already playing when it goes windowless starts on the clock, paused. The
menu shows it, which is the point — a hidden app is not obviously safe.

The pause state observed at the end of one sweep decides whether the interval
that follows counts, so audio starting or stopping mid-interval is credited to
the nearest sweep. Against a grace period measured in minutes, that error is
not perceivable.

Spotify is deliberately not in the default exclusions: the pause covers it
better than an exclusion, which would leave it running forever once the music
stopped.

The pause is a setting, on by default, and the engine reads it on every sweep
rather than latching it into the clock. Turning it off therefore releases apps
already being held, resuming each from the time it had served, instead of
applying only to apps that start playing later.

See `QuitEngine` in `Sources/SmartQuitCore/QuitEngine.swift`.

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
what keeps Smart Quit from ever costing the user work.

See `WorkspaceTerminator` in `Sources/SmartQuitCore/WorkspaceTerminator.swift`.

## A refused quit is not retried

An app that survives a quit request is not asked again until it shows a window.

`terminate()` returning `false`, or the app still running ten seconds later, both
move it to a `surrendered` state. Without that state the app would come back up
for consideration on the next sweep and be asked to quit on every one of them
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

Finder and Smart Quit itself are never quit, and neither is anything on the user's exclude list.

Finder has no meaningful windowless state and quitting it degrades the system.
Exclusions are stored by bundle identifier and seeded on first run only, so an
app the user deliberately un-excludes does not come back on the next launch.

The seeded list covers apps whose value is in staying running with no window at
all — Mail fetching in the background, a terminal whose session outlives its
window. Media players are not on it, because the audio pause protects them for
exactly as long as they need it.

See `DefaultExclusions` in `Sources/SmartQuitCore/DefaultExclusions.swift`.

## One sweep, not one timer per app

A single repeating timer sweeps every application, every three seconds.

A sweep costs about five milliseconds once the Accessibility caches are warm, so
the interval is not set by how long the work takes. It is set by what the work
is: a round trip to every running application, which wakes each of them. That is
why this is seconds rather than milliseconds, and why it is a poor thing to do
more often than the answer can change.

A timer per app would mean dozens of timers waking the CPU independently. One
sweep also gives a consistent view: every decision in a pass is made against the
same instant and the same list of running apps.

Listing apps and applying decisions happen on the main queue. The Accessibility
window counting and the audio lookup between them run on a utility queue,
because those calls are synchronous and can block. A sweep that overruns the interval is skipped rather
than queued behind the one in flight.

Nothing in the engine or the sweeper is synchronised, so both are main queue
only. The background hop is given no access to the sweeper's state — it works
from values captured before it starts — and the entry points assert the queue
rather than trusting callers.

See `AppSweeper` in `Sources/SmartQuitCore/AppSweeper.swift`.

## Grace periods

The grace period defaults to five minutes and can be set globally or per app.

A per-app override takes precedence over the global value. Overrides are stored
by bundle identifier and survive relaunches. The menu offers 1, 2, 5, 10 and 30
minutes plus a custom value.

See `Settings` in `Sources/SmartQuitCore/Settings.swift`.

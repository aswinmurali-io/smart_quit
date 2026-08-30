# Interface

The menu bar item and its menu, and why the menu's content is modelled as data rather than built directly in AppKit.

## The menu is data

`MenuModel` in `Sources/SmartQuitCore/MenuModel.swift` builds the menu as a tree of
`MenuNode` values. `StatusItemController` renders that tree into AppKit and
dispatches the resulting actions.

Structure and wording are the parts of a menu that are worth reviewing and easy
to get wrong, and building them directly into `NSMenu` puts both out of reach of
tests. As data, the whole menu — its order, its labels, which item is checked —
is asserted in `MenuModelTests`.

## Permission leads the menu

When Accessibility permission is missing, the warning and the link to System
Settings come before everything else.

Without that permission Smart Quit cannot see windows, so nothing else in the menu
has any effect. Settings the user cannot act on should not sit above the reason
they cannot act on them.

## The two switches sit together

"Quit idle apps" and "Pause apps playing audio" are both top-level rows, above the first separator.

Everything below them decides *when* an app is quit; these two decide *whether*
it is quit at all. Putting the audio pause in a submenu beside the grace periods
would file it with the timing settings it is not one of.

## Opening the menu sweeps

The header reads "On the clock — checks every 3s". Opening the menu sweeps as well, silently.

An unchanged list is the normal case, and nothing else in the menu distinguishes
"nothing has changed" from "this stopped updating". The interval comes from
`AppSweeper.interval` rather than being written out, so the two cannot drift.

Waiting on the timer alone meant the list could be a full interval behind at the
moment someone looked at it, so `menuWillOpen` starts a sweep — opening the menu
is a refresh rather than a read of whatever the last one left.

The header does not mention it. Nobody has to open the menu to keep the list
honest, and saying so would turn a status line into instructions for a thing
that happens by itself.

That sweep finishes while the menu is on screen, and folding its result in is
where the care goes. Countdown labels already tick on their own timer, so a
rebuild is needed only when the set of listed apps changes — and a rebuild is
exactly what collapses a submenu the user is reading. `sweepCompleted()`
compares the countdown identities against what is rendered and rebuilds only on
a real change.

## The empty state tells the truth

With no apps on the clock the menu says "Nothing waiting to quit"; without
permission it says "Can't see windows without permission"; when paused, "Paused".

These are three different situations and only one of them means nothing is
waiting. Reporting the wrong one would tell the user the app is working when it
is not.

## The icon carries state

The status item is an hourglass: empty when nothing is waiting, bottom-half
filled when apps are on the clock, dimmed when Smart Quit is paused.

A paused clock does not count as on the clock here. It is going nowhere for as
long as the audio lasts, and a filled hourglass would promise a quit that cannot
happen — the icon says what the menu says.

This was a `moon.zzz` glyph, which sat a few slots away from the system Focus
moon in the menu bar and read as a duplicate of it.

## Countdowns tick without a rebuild

The menu is rebuilt when it opens; while it is open, a one-second timer updates
only the countdown labels.

Rebuilding the whole menu each second would collapse any submenu the user has
open. Countdown rows carry their pid so their labels can be found and updated in
place — pid rather than bundle identifier, because two instances of one app are
two clocks and a bundle identifier cannot tell them apart.

A finished sweep rebuilds only when the set of listed pids changes. The
comparison is on a set, not a list: the rows are sorted by remaining time and
pause state, so two of them swapping places is not a reason to tear down a
submenu somebody is reading.

The row's text is built by `MenuModel` rather than by the status item, so the
label written on a tick is the one the menu was built with.

## A paused countdown says why

An app whose clock is held reads "paused (playing audio)" in place of a time.

The frozen number would be noise: what the user needs to know is that the app is
safe for as long as it keeps playing, not what it will resume from. Paused rows
sort below live ones, so an app that is about to be quit is never pushed down by
one that is going nowhere.

## The version sits next to the update check

The menu shows "Version 0.2.0" as a label, directly above "Check for Updates…".

A version nobody can read is no use the moment someone is reporting a bug, and
the page they would go to about it is the natural thing to put it beside.

Reading the version can fail — under `xctest` `Bundle.main` is the test runner,
not an app bundle — so `AppInfo.version` is optional and the row is omitted
rather than showing a placeholder. The update check is offered either way: not
knowing which version is running is exactly when someone wants to go and look.

## Checking for updates opens a page

"Check for Updates…" opens the project's releases page. It does not check anything.

There is no updater, and adding one would mean a utility whose job is quitting
other applications also downloading and replacing itself in the background.
Opening the page leaves the decision, and the download, with the person.

See `AppInfo` in `Sources/SmartQuitCore/AppInfo.swift`.

## The app in front is named, and its row marked

The menu names the app in front above the clock, and marks that app's countdown row "(foreground)".

The frontmost app is the one exception the clock cannot account for on its own:
its countdown runs to zero and stays there, because an app is never quit while
someone is looking at it. Unmarked, that reads as the app being stuck.

Being in front and playing audio are the two reasons a row can sit still, so
they share one parenthetical — "paused (playing audio, foreground)" — rather
than accumulating brackets.

The name is recorded as activations happen, not read when the menu asks. Opening
the menu makes Smart Quit active, and Smart Quit is an accessory app that never
appears in `regularApps()`, so the app in front reads as nothing at precisely
the moment the menu needs it — asking at that point answers nothing, every time.

`StatusItemController` observes `NSWorkspace.didActivateApplicationNotification`
instead, filtering to regular apps by the same rule `regularApps()` uses. That
filter is what keeps Smart Quit itself from becoming the answer.

## Apps with windows are listed inline

"With windows — 5" heads one indented row per app, each with its window count.

Inline, matching the clock section above it. Both answer the same question —
what is going on right now — and putting one behind a disclosure arrow made them
read as different kinds of thing, one a status and the other a setting. The
count stays in the heading so the size of the list is legible before the eye
reaches it.

The rows come from the last sweep, held by `AppSweeper` because nothing else
holds it: the engine drops an app the moment it knows it is not a candidate, so
apps that have windows exist nowhere else by the time the menu wants them.

They are counted by the same rule the quitting logic uses, so an app whose only
window has no standard subrole — Finder and its desktop — is absent from this
list for the same reason it is a quit candidate elsewhere. An unreadable count
keeps an app out too: it is not evidence of a window, the same way it is not
evidence of none.

Before any sweep has finished, the heading reads "With windows" over "Not
checked yet" rather than "With windows — 0". `AppSweeper.lastSweep` is `nil`
until it has something to report, so the menu can tell "nothing has a window"
apart from "nobody has looked" — the same distinction the window count draws
with `Int?`.

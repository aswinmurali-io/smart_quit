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

The header reads "On the clock — checks every 15s". Opening the menu sweeps as well, silently.

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

This was a `moon.zzz` glyph, which sat a few slots away from the system Focus
moon in the menu bar and read as a duplicate of it.

## Countdowns tick without a rebuild

The menu is rebuilt when it opens; while it is open, a one-second timer updates
only the countdown labels.

Rebuilding the whole menu each second would collapse any submenu the user has
open. Countdown rows carry their bundle identifier so their labels can be found
and updated in place.

The row's text is built by `MenuModel` rather than by the status item, so the
label written on a tick is the one the menu was built with.

## A paused countdown says why

An app whose clock is held reads "paused (playing audio)" in place of a time.

The frozen number would be noise: what the user needs to know is that the app is
safe for as long as it keeps playing, not what it will resume from. Paused rows
sort below live ones, so an app that is about to be quit is never pushed down by
one that is going nowhere.

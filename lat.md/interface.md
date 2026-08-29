# Interface

The menu bar item and its menu, and why the menu's content is modelled as data rather than built directly in AppKit.

## The menu is data

`MenuModel` in `Sources/LingererCore/MenuModel.swift` builds the menu as a tree of
`MenuNode` values. `StatusItemController` renders that tree into AppKit and
dispatches the resulting actions.

Structure and wording are the parts of a menu that are worth reviewing and easy
to get wrong, and building them directly into `NSMenu` puts both out of reach of
tests. As data, the whole menu — its order, its labels, which item is checked —
is asserted in `MenuModelTests`.

## Permission leads the menu

When Accessibility permission is missing, the warning and the link to System
Settings come before everything else.

Without that permission Lingerer cannot see windows, so nothing else in the menu
has any effect. Settings the user cannot act on should not sit above the reason
they cannot act on them.

## The empty state tells the truth

With no apps on the clock the menu says "Nothing waiting to quit"; without
permission it says "Can't see windows without permission"; when paused, "Paused".

These are three different situations and only one of them means nothing is
waiting. Reporting the wrong one would tell the user the app is working when it
is not.

## The icon carries state

The status item is an hourglass: empty when nothing is waiting, bottom-half
filled when apps are on the clock, dimmed when Lingerer is paused.

This was a `moon.zzz` glyph, which sat a few slots away from the system Focus
moon in the menu bar and read as a duplicate of it.

## Countdowns tick without a rebuild

The menu is rebuilt when it opens; while it is open, a one-second timer updates
only the countdown labels.

Rebuilding the whole menu each second would collapse any submenu the user has
open. Countdown rows carry their bundle identifier so their labels can be found
and updated in place.

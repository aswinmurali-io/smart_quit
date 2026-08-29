# Contributing

Bug reports, ideas and pull requests are all welcome. This file covers what you
need to know before opening one.

## Getting set up

You need macOS 14.2 or later and the Xcode command line tools. There is no
`.xcodeproj` — Smart Quit is a Swift package.

```bash
swift test          # the whole suite, milliseconds
./Scripts/build-app.sh   # assembles dist/Smart Quit.app
```

The app does nothing without Accessibility permission. Grant it to the bundle
you built, and remember that macOS keys the grant to the code signature: an
ad-hoc signature changes on every build, so the grant goes stale and has to be
cleared with `tccutil reset Accessibility com.smartquit.SmartQuit`. Signing with
an Apple Development certificate avoids this — see **Install** in the README.

## Read `lat.md/` first

[`lat.md/`](../lat.md) is the design record: why the Accessibility API rather
than `CGWindowList`, why an unknown window count is not zero, why state is keyed
by pid, why a refused quit is never retried. Most "why is it done this way"
questions are answered there, and a change that contradicts it needs to say so.

If you have [lat.md](https://www.npmjs.com/package/lat.md) installed,
`lat search "..."` finds the relevant section. If you don't, read the files —
they're plain markdown.

Changing behaviour means updating the matching section. `lat check` validates
the cross-references.

## Tests

The decision engine takes the current time as a parameter, so timing is tested
exactly rather than by sleeping. Follow that: a test that sleeps will be
rejected.

Window counting is tested at its seams — the subrole filter, and the mapping
from `AXError` to "no windows" versus "unknown" — not against a live window
server. New platform code should be shaped the same way, with a protocol at the
boundary and a fake in `Tests/SmartQuitCoreTests/Fakes.swift`.

A bug fix wants a test that fails before it and passes after.

## Pull requests

- One concern per pull request.
- Keep `swift test` green; CI runs it on every push.
- Write the commit subject as an instruction — "Stop warning about notarization
  while notarizing", not "fixed bug".
- Say what a reviewer should look at, and what you were unsure about.

Formatting follows what's already in the file. There is no linter to satisfy.

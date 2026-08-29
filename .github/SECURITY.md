# Security policy

Smart Quit runs with Accessibility permission and can ask other applications to
quit, so a defect here can reach beyond the app itself. Reports are welcome.

## Supported versions

The latest release is the only supported version. Fixes ship in a new release
rather than as patches to an older tag.

## Reporting a vulnerability

Report privately through GitHub — open
[a draft security advisory](https://github.com/aswinmurali-io/smart_quit/security/advisories/new).
It stays private until a fix is released.

Please don't open a public issue for a vulnerability.

Include what you have: the macOS version, the Smart Quit version from the menu,
the steps that reproduce it, and what an attacker gets out of it. Expect a first
reply within a week.

## What is in scope

The interesting cases are the ones where the app acts on something it shouldn't:

- Quitting an app that has windows, is playing audio, or is excluded — the
  states the engine is meant to protect.
- Anything that turns the Accessibility grant or the Apple Event path into more
  access than reading window counts and sending quit events.
- A release artefact that fails `codesign --verify` or `stapler validate`, or
  whose contents don't match this repository.

## What is not

- An app refusing to quit because it has unsaved work. That is
  `terminate()` behaving correctly, not a bug.
- Anything that needs an attacker to already have code execution as your user,
  since at that point they can send quit events themselves.
- Reports against a locally built, ad-hoc signed bundle where the finding is the
  ad-hoc signature.

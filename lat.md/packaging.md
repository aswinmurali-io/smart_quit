# Packaging

How the Swift package becomes an app bundle a person can install, and what signing it costs.

## The product name and the code name differ

The app is "Smart Quit" to a person and `SmartQuit` to the build.

`CFBundleName` and `CFBundleDisplayName` carry the spaced name, and so does every
string the user reads — the menu's quit row, the status item's tooltip, the
login-item alert. The executable, the SwiftPM targets, the module and the bundle
identifier `com.smartquit.SmartQuit` keep the closed-up form, because renaming
those would change the identity macOS keys permissions to for no visible gain.

The bundle on disk is `Smart Quit.app`, matching the display name so Finder and
the menu bar agree. `Scripts/build-app.sh` holds the two names apart as
`APP_NAME` and `TARGET`.

## A bundle, not a bare executable

Swift Package Manager emits an executable; the app has to be a bundle.

`LSUIElement`, the bundle identifier, the icon and `SMAppService` login-item
registration are all read from `Info.plist`, which only exists inside a bundle.
`Scripts/build-app.sh` assembles one around the built binary rather than the
project carrying an Xcode target for the same purpose.

## Signing keeps the Accessibility grant

The app is signed with a real certificate because an ad-hoc signature loses the user's permission on every rebuild.

TCC records the Accessibility grant against the app's code signature. An ad-hoc
signature's cdhash changes with every build, so the next build is a different app
as far as macOS is concerned: the checkbox in System Settings stays ticked while
the app is told it has no permission, and re-ticking does not fix it — the stale
record has to be cleared with
`tccutil reset Accessibility com.smartquit.SmartQuit`.

Any Apple Development certificate gives a stable identity, and the grant then
survives rebuilds. The identity is matched by Apple ID rather than by taking the
first certificate in the keychain: a keychain routinely holds work certificates
whose private keys are not usable, and signing with one fails late with
`errSecInternalComponent` and no indication of which key it wanted.
`SMARTQUIT_SIGNING_ACCOUNT` chooses the account; `CODESIGN_IDENTITY` names an
identity outright.

## Distribution needs Developer ID and notarization

`Scripts/release.sh` produces the stapled disk image; `Scripts/build-app.sh` produces something only this machine will run.

A development certificate is not enough for anyone else's Mac. Without a
Developer ID Application certificate, the hardened runtime and a trip through
Apple's notary service, Gatekeeper refuses the app on a machine that has never
seen it, and the user is told it is damaged rather than anything true.

The disk image is what gets notarized and stapled, not the app inside it: a
stapled `.dmg` can be verified offline, where stapling the app alone leaves the
container unchecked.

`Resources/SmartQuit.entitlements` is deliberately empty. The app loads no
plug-ins, generates no code and reads no protected data; the Accessibility and
Apple Events access it needs is granted by the user at runtime, not by an
entitlement. The file exists so that set is stated rather than inferred from its
absence.

## The icon is drawn, not checked in

`Scripts/make-icon.swift` renders the `.icns` from paths.

A generated icon can be reviewed in a diff and adjusted in one place, where a
binary can only be replaced. The hourglass is drawn by hand rather than rendered
from the `hourglass` SF Symbol the menu bar uses, because the SF Symbols licence
does not allow a symbol to be used as an app icon.

# Packaging

How the Swift package becomes an app bundle a person can install, and what signing it costs.

## The disk image is named for its version

`Scripts/make-dmg.sh` writes `SmartQuit-<version>.dmg`, reading the version from `Info.plist`.

`Info.plist` is the single place a release number lives; both the packaging and
release scripts read `CFBundleShortVersionString` from it rather than carrying
their own copy. A file called `SmartQuit.dmg` says nothing about what is inside
it, and two of them in a Downloads folder are indistinguishable — the second
arrives as `SmartQuit-1.dmg`, which is worse than useless.

`CFBundleVersion` stays a plain build counter, separate from the version people
see.

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

## Packaging is split from notarizing

`Scripts/make-dmg.sh` builds the disk image; `Scripts/release.sh` notarizes what it built.

The two are separate because they have different prerequisites. Building a
`.dmg` needs nothing but the app, so it works with whatever signature is to
hand; notarizing needs a Developer ID certificate and a `notarytool` profile.
Folding them together would mean no disk image at all until both exist.

An unnotarized image is still useful — it installs on the machine that built it —
so the script says what it produced rather than implying more. macOS treats an
unnotarized app under quarantine as damaged rather than untrusted, which reads
as a broken download, so the distinction is worth stating where someone will see
it.

## The window is arranged by Finder, on a read-write image

The disk image is built twice: read-write so it can be arranged, then converted to the compressed image that ships.

Icon positions, window size, icon size and the background picture all live in
the volume's `.DS_Store`, and nothing writes one but Finder. `hdiutil` cannot
set any of it. So the image is created read-write, mounted, driven through Apple
Events, and only then converted — the conversion carries the `.DS_Store` across.

Finder writes that file when the window closes, not when the properties are set.
Detaching the volume with the window still open loses the entire layout while
every command appears to have succeeded, so the script closes the window, waits,
and then checks the file exists before converting. Without that check an
unstyled image is indistinguishable from a styled one until someone opens it.

A volume left mounted from an earlier run is the other way this fails quietly:
the new image mounts as "Smart Quit 1" while Finder is told to arrange "Smart
Quit", and obliges — on the stale volume. The script detaches leftovers first
and reads the mount point back from `hdiutil` rather than assuming it.

Scripting Finder needs Automation permission. Refused, the layout is skipped and
reported rather than failing the build: an unarranged image still installs.

## Window bounds are the frame, not the canvas

The window is asked for the background's height plus a title bar, and the path and status bars are switched off.

Finder's `bounds` measures the whole frame, chrome included, while the icons and
the background sit in what is left underneath. Asking for 400pt therefore gave a
347pt canvas — 400 less a 28pt title bar and a 25pt path bar — so icons centred
against 400 sat low, and the bottom of the background was never on screen.

The path and status bars are Finder-wide preferences, so they arrive switched on
for anyone who uses them and the canvas is a different size for different people.
Turning both off leaves the title bar as the only chrome, which is a known 28pt
and can simply be added back.

## Distribution needs Developer ID and notarization

`Scripts/release.sh` produces the stapled disk image; `Scripts/build-app.sh` produces something only this machine will run.

A development certificate is not enough for anyone else's Mac. Without a
Developer ID Application certificate, the hardened runtime and a trip through
Apple's notary service, Gatekeeper refuses the app on a machine that has never
seen it, and the user is told it is damaged rather than anything true.

The disk image is what gets notarized and stapled, not the app inside it: a
stapled `.dmg` can be verified offline, where stapling the app alone leaves the
container unchecked.

Only the image carries a ticket, though, so an app dragged out of it has none of
its own. Gatekeeper then asks Apple on first launch, which is fine online and a
gap offline. Closing it means notarizing twice — the app, stapled, then the
image built around it — which is a second round trip through the notary service
for a case nobody has hit.

`make-dmg.sh` reports the image as unnotarized because, on its own, it is.
`release.sh` sets `SMARTQUIT_WILL_NOTARIZE` to suppress that: the warning is
true when it prints and false a minute later, which is worse than saying
nothing.

The image is signed too, and only in `release.sh`. It has to happen after the
image exists — `hdiutil` rewrites the file when it compresses, dropping any
signature already on it — which is why `make-dmg.sh` leaves it unsigned, that
and an image it builds alone being undistributable regardless.

Signing is not `--deep`. Apple documents that flag as a verification
convenience and warns against signing with it: it stamps every nested binary
with the same entitlements rather than signing each on its own terms. There is
no nested code here today, which is exactly when a wrong flag goes unnoticed.

Its identifier is pinned to `com.smartquit.SmartQuit.dmg`. Left to itself
`codesign` derives one from the file name and truncates at the first dot, so
`SmartQuit-0.1.0.dmg` signs as `SmartQuit-0`: a different identifier every
release. The signature also needs a real `--timestamp`, because notarization
rejects one without a secure timestamp.

Note that modifying a signed image reads as `code object is not signed at all`
rather than as an invalid signature — the signature sits at the end of the file,
so a change destroys the trailer instead of failing a hash. It is caught either
way, but the message points at the wrong thing.

`Resources/SmartQuit.entitlements` is deliberately empty. The app loads no
plug-ins, generates no code and reads no protected data; the Accessibility and
Apple Events access it needs is granted by the user at runtime, not by an
entitlement. The file exists so that set is stated rather than inferred from its
absence.

## The icon and the disk image background are drawn, not checked in

`Scripts/make-icon.swift` renders the `.icns` from paths, and `Scripts/make-dmg-background.swift` the disk image's backdrop.

A generated icon can be reviewed in a diff and adjusted in one place, where a
binary can only be replaced. The hourglass is drawn by hand rather than rendered
from the `hourglass` SF Symbol the menu bar uses, because the SF Symbols licence
does not allow a symbol to be used as an app icon.

`make-icon.swift` also writes `docs/icon.png` for the README. GitHub cannot
render an `.icns`, and a PNG dropped in by hand would be a second answer to what
the icon looks like — this way there is one drawing and two outputs of it.

The background is a single image at exactly the window's point size. The usual
way to get a crisp one is a two-page TIFF from `tiffutil -cathidpicheck`, and it
misbehaves: Finder takes the 2x page and draws it at 1:1 anchored bottom-left,
so the window shows the lower-left quarter of the artwork at double size. Being
drawn in the right place matters more than having sharp edges.

It carries no text for the same reason — soft type is obvious where a soft
gradient is not, and an arrow pointing at the Applications folder says what a
caption would have. The arrow is positioned from the same constants as the icons
in `Scripts/make-dmg.sh`; the two files have to agree or it points at nothing.

Disk image backgrounds do not follow the system appearance, so it commits to a
light palette rather than serving both badly. Nor can the `.app` extension be
hidden from here: `AppleShowAllExtensions` overrides the per-file flag, and
readers who have not set it see no extension anyway.

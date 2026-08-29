#!/bin/bash
#
# Packages dist/Smart Quit.app into dist/SmartQuit-<version>.dmg.
#
# This is the packaging half of a release, split out so a disk image can be
# built with whatever signature the app already has. Scripts/release.sh calls it
# and then notarizes the result; run directly, it produces a disk image that
# installs fine on this Mac and trips Gatekeeper on anyone else's — see the note
# it prints at the end.
#
# The image is built twice over: once read-write, so Finder can be told where
# the icons go and what sits behind them, and then converted to the compressed
# read-only image that ships. Window geometry lives in the volume's .DS_Store,
# and the only way to write one is to mount a volume and arrange it.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Smart Quit"
BUNDLE="dist/${APP_NAME}.app"

# The image is named for the version it holds, read from Info.plist so there is
# one place a release number lives. A download called SmartQuit.dmg says nothing
# about what it contains, and two of them in a Downloads folder are
# indistinguishable — the second arrives as "SmartQuit-1.dmg".
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="dist/SmartQuit-${VERSION}.dmg"
STAGING="build/dmg"
RW_IMAGE="build/dmg-rw.dmg"

# Shared with Scripts/make-dmg-background.swift, which draws the arrow between
# these two points. Change one and you must change the other.
WINDOW_WIDTH=640
WINDOW_HEIGHT=400

# Finder's window "bounds" measures the whole frame, chrome included, while the
# icons and the background live in what is left underneath it. Asking for a
# 400pt window therefore gave a 347pt canvas — 400 less the title bar and the
# path bar — and centring the icons in 400 sat them low in 347. The path and
# status bars are turned off below, so the title bar is all that remains to add
# back.
TITLE_BAR_HEIGHT=28
ICON_CENTER_Y=190
APP_ICON_X=170
APPLICATIONS_X=470

if [[ ! -d "${BUNDLE}" ]]; then
    echo "==> No app bundle yet"
    ./Scripts/build-app.sh
fi

# MARK: Stage

echo "==> Staging"
rm -rf "${STAGING}" "${RW_IMAGE}" "${DMG}"
mkdir -p "${STAGING}/.background"
cp -R "${BUNDLE}" "${STAGING}/"
# A symlink to /Applications, so the disk image is a drag-and-drop installer
# rather than something the user has to know where to put.
ln -s /Applications "${STAGING}/Applications"

echo "==> Drawing the background"
# One image, at exactly the window's point size. A two-page hidpi TIFF is the
# usual way to get a crisp background and it misbehaves here: Finder draws the
# 2x page at 1:1 anchored bottom-left, so the window shows a quarter of the
# artwork at double size.
swift Scripts/make-dmg-background.swift >/dev/null
cp build/dmg-background/background.png "${STAGING}/.background/background.png"

# MARK: Arrange
#
# hdiutil cannot set window geometry, so the layout is applied by mounting a
# read-write image and driving Finder. Everything Finder is told here ends up in
# the volume's .DS_Store, which the conversion below carries into the final
# image.

SIZE_MB=$(( $(du -sm "${STAGING}" | cut -f1) + 20 ))

echo "==> Building a read-write image"
hdiutil create \
    -srcfolder "${STAGING}" \
    -volname "${APP_NAME}" \
    -fs HFS+ \
    -format UDRW \
    -size "${SIZE_MB}m" \
    "${RW_IMAGE}" >/dev/null

# Detach any volume left over from an earlier run. Without this the new image
# mounts as "Smart Quit 1" while Finder is told to arrange "Smart Quit" — it
# obliges, on the stale volume, and the layout silently goes nowhere.
while read -r stale; do
    [[ -n "${stale}" ]] && hdiutil detach "${stale}" -force -quiet 2>/dev/null || true
# Matched exactly, on the whole mount point. A substring match would also
# take out a volume of the user's called "Smart Quit Backup", force-detaching
# something this script never created.
done < <(hdiutil info | awk -F'\t' -v v="/Volumes/${APP_NAME}" '$NF == v {print $1}')

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_IMAGE}")"
DEVICE="$(echo "${ATTACH}" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
# Read the mount point back rather than assuming it: if something still holds
# the name, macOS appends a number and every path below has to follow.
MOUNT="$(echo "${ATTACH}" | grep -oE '/Volumes/.*$' | head -1)"
VOLUME="$(basename "${MOUNT}")"

# Always unmount, including on a failure part-way through arranging — a leaked
# mount blocks the next run, which then fails for an unrelated-looking reason.
cleanup() {
    hdiutil detach "${DEVICE}" -quiet 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Arranging the window"
# Finder is scripted through Apple Events, which macOS gates behind the
# Automation permission. Denied, the layout is skipped rather than the build
# failing: an unstyled image still installs.
# Judged by exit status, not by whether anything reached stderr: osascript
# writes warnings there too, and treating those as failure reports an
# unstyled image when the layout in fact applied.
ARRANGE_LOG="$(mktemp)"
if osascript >/dev/null 2>"${ARRANGE_LOG}" <<APPLESCRIPT
set backgroundImage to POSIX file "${MOUNT}/.background/background.png" as alias
tell application "Finder"
    tell disk "${VOLUME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- The path bar is the strip along the bottom. It is a Finder-wide
        -- preference, so it arrives switched on for anyone who uses it, eating
        -- into the canvas the background was drawn for.
        set pathbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT + TITLE_BAR_HEIGHT))}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to backgroundImage

        set position of item "${APP_NAME}.app" of container window to {${APP_ICON_X}, ${ICON_CENTER_Y}}
        set position of item "Applications" of container window to {${APPLICATIONS_X}, ${ICON_CENTER_Y}}

        update without registering applications
        -- Closing the window is what makes Finder write .DS_Store. Leaving it
        -- open and detaching underneath it loses the whole layout.
        delay 2
        close
        delay 1
    end tell
end tell
APPLESCRIPT
then
    ARRANGED=1
else
    ARRANGED=0
    echo "    Finder could not be scripted, so the image keeps the default layout:"
    sed 's/^/    /' "${ARRANGE_LOG}"
    echo "    If this is a permission error, grant Automation access for Finder to"
    echo "    whichever app runs this script in System Settings > Privacy & Security."
fi
rm -f "${ARRANGE_LOG}"

# Let Finder finish writing .DS_Store before the volume goes away.
sync
sleep 2

# The layout lives entirely in this file. Checking for it here turns a silent
# "the image came out unstyled" into something the build actually reports.
if [[ "${ARRANGED}" == "1" && ! -f "${MOUNT}/.DS_Store" ]]; then
    ARRANGED=0
    echo "    Finder reported success but wrote no .DS_Store — layout not saved."
fi

hdiutil detach "${DEVICE}" -quiet
trap - EXIT

# MARK: Compress

echo "==> Compressing"
hdiutil convert "${RW_IMAGE}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG}" >/dev/null

rm -rf "${STAGING}" "${RW_IMAGE}"

# MARK: Report
#
# Say what this disk image will actually do on someone else's Mac, rather than
# leaving them to discover it from a "damaged" dialog. spctl answers the
# question Gatekeeper asks; a non-zero exit here is information, not a failure.

echo
[[ "${ARRANGED}" == "1" ]] || echo "Layout: default (Finder was not scriptable)."

if spctl --assess --type open --context context:primary-signature "${DMG}" 2>/dev/null; then
    echo "Notarized: this installs cleanly anywhere."
else
    echo "Built ${DMG} — NOT notarized."
    echo
    echo "It installs fine on this Mac. On any other Mac, macOS will refuse it:"
    echo "downloading it attaches a quarantine flag, and an unnotarized app under"
    echo "quarantine is reported as damaged rather than merely untrusted."
    echo
    echo "To share it, run ./Scripts/release.sh instead — that needs a Developer ID"
    echo "certificate and a notarytool profile. To open this one on another Mac,"
    echo "the quarantine flag has to be cleared by hand:"
    echo "  xattr -d com.apple.quarantine /path/to/$(basename "${DMG}")"
fi

echo
ls -lh "${DMG}"

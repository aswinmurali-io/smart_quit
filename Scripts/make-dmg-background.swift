#!/usr/bin/env swift
// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only
//
// Draws the disk image's window background into build/dmg-background/.
//
// Generated for the same reason as the app icon: a drawn background can be
// reviewed in a diff and adjusted in one place.
//
// One image, at exactly the window's point size. The usual trick for a crisp
// background is a two-page TIFF built with `tiffutil -cathidpicheck`, and it
// does not work here: Finder takes the 2x page and draws it at 1:1, anchored
// bottom-left, so the window shows the lower-left quarter of the artwork
// blown up to double size. A single-resolution image is drawn where it is
// meant to go, which matters more than its edges being perfectly sharp.
//
// Nothing here is text, for the same reason. Soft type is obvious in a way a
// soft gradient is not, and an arrow pointing at the Applications folder says
// what a caption would have said.
//
// The geometry has to match the icon positions in make-dmg.sh: the background
// is mapped 1:1 onto the window's content area, so the arrow only points
// between the icons if both files agree on where they are.

import AppKit
import Foundation

// MARK: - Layout
//
// Shared with make-dmg.sh. Change one and you must change the other.

let windowWidth: CGFloat = 640
let windowHeight: CGFloat = 400
let iconCenterY: CGFloat = 190
let appIconCenterX: CGFloat = 170
let applicationsCenterX: CGFloat = 470

// MARK: - Drawing

private func drawBackground(width: CGFloat, height: CGFloat) {
    // A pale, slightly warm ground. Disk image backgrounds do not follow the
    // system appearance — Finder shows this image whatever the theme — so it
    // commits to light rather than trying to serve both badly.
    let gradient = NSGradient(
        starting: NSColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1),
        ending: NSColor(red: 0.93, green: 0.91, blue: 0.97, alpha: 1)
    )
    gradient?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
}

private func drawArrow() {
    // Between the two icons, clear of both. The icons are 128pt, so their edges
    // sit 64pt either side of their centres.
    let startX = appIconCenterX + 78
    let endX = applicationsCenterX - 78
    // Flipped: Finder measures icon positions from the top of the window, and
    // the layout constants above follow it.
    let y = windowHeight - iconCenterY

    let violet = NSColor(red: 0.52, green: 0.42, blue: 0.82, alpha: 0.75)
    violet.setStroke()
    violet.setFill()

    let headLength: CGFloat = 22
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: startX, y: y))
    shaft.line(to: NSPoint(x: endX - headLength, y: y))
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: endX, y: y))
    head.line(to: NSPoint(x: endX - headLength, y: y + 14))
    head.line(to: NSPoint(x: endX - headLength, y: y - 14))
    head.close()
    head.fill()
}

private func render() -> NSBitmapImageRep? {
    let width = windowWidth
    let height = windowHeight

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    drawBackground(width: width, height: height)
    drawArrow()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/dmg-background")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

guard let rep = render(),
      let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error: could not render the background\n".utf8))
    exit(1)
}
try data.write(to: output.appendingPathComponent("background.png"))

print("Wrote \(output.path)")

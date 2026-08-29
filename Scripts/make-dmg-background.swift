#!/usr/bin/env swift
//
// Draws the disk image's window background into build/dmg-background/.
//
// Generated for the same reason as the app icon: a drawn background can be
// reviewed in a diff and adjusted in one place. The output is a two-page TIFF
// rather than a PNG, because that is the only way to give Finder a retina
// representation — it picks the 2x page on a Retina display and the 1x page
// elsewhere. Scripts/make-dmg.sh combines the two with `tiffutil`.
//
// The geometry here has to match the icon positions in make-dmg.sh: the
// background is mapped 1:1 onto the window's content area, so the arrow is only
// pointing between the icons if both agree on where they are.

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

private func drawArrow(scale: CGFloat) {
    // Between the two icons, clear of both. The icons are 128pt, so their edges
    // sit 64pt either side of their centres.
    let startX = (appIconCenterX + 78) * scale
    let endX = (applicationsCenterX - 78) * scale
    // Flipped: Finder measures icon positions from the top of the window, and
    // the layout constants above follow it.
    let y = (windowHeight - iconCenterY) * scale

    let violet = NSColor(red: 0.52, green: 0.42, blue: 0.82, alpha: 0.75)
    violet.setStroke()
    violet.setFill()

    let headLength: CGFloat = 22 * scale
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: startX, y: y))
    shaft.line(to: NSPoint(x: endX - headLength, y: y))
    shaft.lineWidth = 6 * scale
    shaft.lineCapStyle = .round
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: endX, y: y))
    head.line(to: NSPoint(x: endX - headLength, y: y + 14 * scale))
    head.line(to: NSPoint(x: endX - headLength, y: y - 14 * scale))
    head.close()
    head.fill()
}

private func draw(_ text: String, size: CGFloat, weight: NSFont.Weight,
                  color: NSColor, centerY: CGFloat, width: CGFloat, scale: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * scale, weight: weight),
        .foregroundColor: color,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let measured = attributed.size()
    attributed.draw(at: NSPoint(
        x: (width - measured.width) / 2,
        y: (windowHeight - centerY) * scale - measured.height / 2
    ))
}

private func render(scale: CGFloat) -> NSBitmapImageRep? {
    let width = windowWidth * scale
    let height = windowHeight * scale

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

    // Tell the rep its point size, so the 2x page is tagged as retina rather
    // than as a larger image.
    rep.size = NSSize(width: windowWidth, height: windowHeight)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    drawBackground(width: width, height: height)
    drawArrow(scale: scale)
    draw("Smart Quit", size: 26, weight: .semibold,
         color: NSColor(white: 0.18, alpha: 1), centerY: 62, width: width, scale: scale)
    draw("Drag it onto Applications to install", size: 13, weight: .regular,
         color: NSColor(white: 0.45, alpha: 1), centerY: 330, width: width, scale: scale)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/dmg-background")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    guard let rep = render(scale: scale),
          let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: could not render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: output.appendingPathComponent(name))
}

print("Wrote \(output.path)")

#!/usr/bin/env swift
//
// Draws Resources/SmartQuit.icns.
//
// The icon is generated rather than checked in as a binary so it can be read,
// reviewed and adjusted in a diff like everything else. SF Symbols are not used
// here — their licence forbids it in app icons — so the hourglass is drawn from
// paths, shaped to echo the `hourglass` symbol in the menu bar without being it.

import AppKit
import Foundation

// MARK: - Geometry

/// Apple's macOS icon grid: the rounded square occupies 824pt of a 1024pt
/// canvas, leaving room for the shadow every other macOS icon has.
private let canvas: CGFloat = 1024
private let plateInset: CGFloat = 100
private let plateRadius: CGFloat = 185

private func scaled(_ value: CGFloat, to size: CGFloat) -> CGFloat {
    value / canvas * size
}

// MARK: - Drawing

private func drawPlate(in context: CGContext, size: CGFloat) {
    let inset = scaled(plateInset, to: size)
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: scaled(plateRadius, to: size),
        cornerHeight: scaled(plateRadius, to: size),
        transform: nil
    )

    context.saveGState()
    context.addPath(path)
    context.clip()

    // Indigo to violet, top to bottom. Dark enough that the white glass reads
    // on a light desktop, saturated enough not to disappear on a dark one.
    let colors = [
        CGColor(red: 0.30, green: 0.28, blue: 0.86, alpha: 1),
        CGColor(red: 0.52, green: 0.22, blue: 0.80, alpha: 1),
    ] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: size, y: 0),
            options: []
        )
    }
    context.restoreGState()
}

/// The hourglass: two bars and two bulbs meeting at a waist.
private func drawHourglass(in context: CGContext, size: CGFloat) {
    let unit = { (value: CGFloat) in scaled(value, to: size) }

    let centerX = size / 2
    let top = unit(268)
    let bottom = unit(756)
    let halfWidth = unit(150)
    let barHeight = unit(46)
    let barHalfWidth = unit(186)
    let waist = unit(14)
    let middle = (top + bottom) / 2

    // Flipped: CoreGraphics is bottom-up, and the drop reads better drawn from
    // the top down.
    func y(_ value: CGFloat) -> CGFloat { size - value }

    let glass = CGMutablePath()
    // Upper bulb, tapering into the waist.
    glass.move(to: CGPoint(x: centerX - halfWidth, y: y(top)))
    glass.addLine(to: CGPoint(x: centerX + halfWidth, y: y(top)))
    glass.addQuadCurve(
        to: CGPoint(x: centerX + waist, y: y(middle)),
        control: CGPoint(x: centerX + halfWidth * 0.55, y: y(middle - unit(60)))
    )
    // Lower bulb, mirrored.
    glass.addQuadCurve(
        to: CGPoint(x: centerX + halfWidth, y: y(bottom)),
        control: CGPoint(x: centerX + halfWidth * 0.55, y: y(middle + unit(60)))
    )
    glass.addLine(to: CGPoint(x: centerX - halfWidth, y: y(bottom)))
    glass.addQuadCurve(
        to: CGPoint(x: centerX - waist, y: y(middle)),
        control: CGPoint(x: centerX - halfWidth * 0.55, y: y(middle + unit(60)))
    )
    glass.addQuadCurve(
        to: CGPoint(x: centerX - halfWidth, y: y(top)),
        control: CGPoint(x: centerX - halfWidth * 0.55, y: y(middle - unit(60)))
    )
    glass.closeSubpath()

    context.saveGState()
    context.addPath(glass)
    context.setFillColor(CGColor(gray: 1, alpha: 0.22))
    context.fillPath()

    // The sand, clipped to the glass so it can never spill outside it.
    context.addPath(glass)
    context.clip()
    context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.45, alpha: 1))
    // Settled in the lower bulb: the app's whole point is time having run out.
    context.fill(CGRect(
        x: centerX - halfWidth,
        y: y(bottom),
        width: halfWidth * 2,
        height: unit(150)
    ))
    // A thread still falling, so the icon reads as running rather than spent.
    // It starts at the waist and stops on the mound: crossing into the upper
    // bulb would read as a rod through the glass rather than as sand.
    let moundTop = y(bottom - unit(150))
    context.fill(CGRect(
        x: centerX - unit(9),
        y: moundTop,
        width: unit(18),
        height: y(middle) - moundTop
    ))
    context.restoreGState()

    // A thin edge so the glass keeps its shape against the gradient rather
    // than fading into it at small sizes.
    context.saveGState()
    context.addPath(glass)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
    context.setLineWidth(unit(16))
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // The frame, drawn last so it sits over both glass and sand.
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    for barY in [top, bottom] {
        let rect = CGRect(
            x: centerX - barHalfWidth,
            y: y(barY) - (barY == top ? barHeight : 0),
            width: barHalfWidth * 2,
            height: barHeight
        )
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: barHeight / 2,
            cornerHeight: barHeight / 2,
            transform: nil
        ))
    }
    context.fillPath()
}

// MARK: - Output

private func render(size: CGFloat) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    drawPlate(in: context, size: size)
    drawHourglass(in: context, size: size)
    return context.makeImage()
}

private func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/SmartQuit.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes `iconutil` expects, each at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        guard let image = render(size: pixels) else {
            FileHandle.standardError.write(Data("error: could not render \(pixels)pt\n".utf8))
            exit(1)
        }
        let suffix = scale == 1 ? "" : "@2x"
        try write(image, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

// The README's copy, written from the same drawing so the two cannot drift.
// GitHub cannot render an .icns, and a PNG checked in by hand would be a second
// source of truth for what the icon looks like.
let readmeIcon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs")
try FileManager.default.createDirectory(at: readmeIcon, withIntermediateDirectories: true)

guard let large = render(size: 512) else {
    FileHandle.standardError.write(Data("error: could not render the README icon\n".utf8))
    exit(1)
}
try write(large, to: readmeIcon.appendingPathComponent("icon.png"))

print("Wrote \(iconset.path) and \(readmeIcon.path)/icon.png")

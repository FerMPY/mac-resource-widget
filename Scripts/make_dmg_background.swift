#!/usr/bin/env swift
import AppKit

// Draws the installer DMG background: a dark gradient with a title, an
// instruction line and an arrow pointing from the app icon to the
// Applications folder. Output is a Retina TIFF (1200x800 px / 600x400 pt).
// Run via: swift Scripts/make_dmg_background.swift

let W: CGFloat = 600   // window content size in points
let H: CGFloat = 400
let scale = 2          // Retina

let iconYFromTop: CGFloat = 175   // must match icon positions in package.sh
let appX: CGFloat = 165
let appsX: CGFloat = 435

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W) * scale,
    pixelsHigh: Int(H) * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }
rep.size = NSSize(width: W, height: H)   // point size → marks it as @2x

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("could not create graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Background gradient — deep navy to near-black, matching the app.
NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.15, blue: 0.24, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.11, alpha: 1),
])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// Text is drawn in a y-up coordinate space; topFromTop measures from the top.
func drawCentered(_ s: String, _ attrs: [NSAttributedString.Key: Any], topFromTop: CGFloat) {
    let str = NSAttributedString(string: s, attributes: attrs)
    let size = str.size()
    str.draw(at: NSPoint(x: (W - size.width) / 2, y: H - topFromTop - size.height))
}

drawCentered("Mac Resource Widget", [
    .font: NSFont.systemFont(ofSize: 25, weight: .bold),
    .foregroundColor: NSColor.white,
], topFromTop: 44)

drawCentered("Drag the app onto the Applications folder to install", [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.5),
], topFromTop: 79)

// Arrow from the app icon toward the Applications folder.
let arrowY = H - iconYFromTop                 // y-up
let x1 = appX + 88                            // just past the app icon
let x2 = appsX - 88                           // just before the Applications icon
let accent = NSColor(srgbRed: 0.42, green: 0.86, blue: 0.96, alpha: 0.92)
accent.setStroke()
accent.setFill()

let shaft = NSBezierPath()
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: x1, y: arrowY))
shaft.line(to: NSPoint(x: x2 - 3, y: arrowY))
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: x2 + 10, y: arrowY))
head.line(to: NSPoint(x: x2 - 6, y: arrowY + 11))
head.line(to: NSPoint(x: x2 - 6, y: arrowY - 11))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let tiff = rep.tiffRepresentation else { fatalError("could not encode TIFF") }
let out = URL(fileURLWithPath: "Resources/dmg-background.tiff")
try tiff.write(to: out)
print("✓ \(out.path)")

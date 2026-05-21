#!/usr/bin/env swift
import Cocoa
import CoreGraphics

// Generates AppIcon.iconset/ + AppIcon.icns next to the project root.
// Run via: swift Scripts/make_icon.swift

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = projectRoot.appendingPathComponent("AppIcon.iconset")
let resourcesURL = projectRoot.appendingPathComponent("Resources")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

// MARK: - Drawing

struct RGB { let r, g, b: CGFloat; func cg(_ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) } }

let barColors: [(top: RGB, bottom: RGB)] = [
    (RGB(r: 0.40, g: 0.92, b: 1.00), RGB(r: 0.10, g: 0.65, b: 0.85)),  // cyan
    (RGB(r: 0.78, g: 0.50, b: 1.00), RGB(r: 0.48, g: 0.24, b: 0.82)),  // purple
    (RGB(r: 1.00, g: 0.45, b: 0.75), RGB(r: 0.85, g: 0.20, b: 0.50)),  // pink
    (RGB(r: 1.00, g: 0.72, b: 0.30), RGB(r: 0.90, g: 0.45, b: 0.10)),  // orange
]

let barHeightRatios: [CGFloat] = [0.32, 0.46, 0.62, 0.50]  // visual rhythm, not literal data

func drawIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Squircle background clip (Big Sur ratio)
    let cornerRadius = s * 0.2237
    let fullRect = CGRect(x: 0, y: 0, width: s, height: s)
    let clipPath = CGPath(roundedRect: fullRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()

    // Background gradient — deep navy top to near-black bottom
    let bgGradient = CGGradient(
        colorsSpace: cs,
        colors: [
            RGB(r: 0.13, g: 0.15, b: 0.24).cg(),
            RGB(r: 0.06, g: 0.07, b: 0.12).cg(),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Subtle top highlight (frosted-glass feel)
    let highlight = CGGradient(
        colorsSpace: cs,
        colors: [
            RGB(r: 1, g: 1, b: 1).cg(0.12),
            RGB(r: 1, g: 1, b: 1).cg(0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.55), options: [])

    // Bars
    let barCount = barColors.count
    let barWidth = s * 0.115
    let barSpacing = s * 0.055
    let totalWidth = barWidth * CGFloat(barCount) + barSpacing * CGFloat(barCount - 1)
    let startX = (s - totalWidth) / 2
    let baseY = s * 0.225
    let barCornerRadius = barWidth * 0.32

    for i in 0..<barCount {
        let x = startX + CGFloat(i) * (barWidth + barSpacing)
        let height = s * barHeightRatios[i]
        let barRect = CGRect(x: x, y: baseY, width: barWidth, height: height)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barCornerRadius, cornerHeight: barCornerRadius, transform: nil)

        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()
        let gradient = CGGradient(
            colorsSpace: cs,
            colors: [barColors[i].top.cg(), barColors[i].bottom.cg()] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: x, y: baseY + height),
                               end: CGPoint(x: x, y: baseY),
                               options: [])
        ctx.restoreGState()

        // Soft glow above each bar tip
        ctx.saveGState()
        let tipGlow = CGRect(x: x - barWidth * 0.1, y: baseY + height - barWidth * 0.2,
                             width: barWidth * 1.2, height: barWidth * 0.6)
        let glowGradient = CGGradient(
            colorsSpace: cs,
            colors: [
                barColors[i].top.cg(0.35),
                barColors[i].top.cg(0),
            ] as CFArray,
            locations: [0, 1]
        )!
        let cx = tipGlow.midX
        let cy = tipGlow.midY
        ctx.drawRadialGradient(glowGradient,
                               startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: barWidth * 0.7,
                               options: [])
        ctx.restoreGState()
    }

    // Inner border (1px equivalent, scaled) for crisper edges
    ctx.resetClip()
    ctx.addPath(CGPath(roundedRect: fullRect.insetBy(dx: 0.5, dy: 0.5),
                       cornerWidth: cornerRadius - 0.5, cornerHeight: cornerRadius - 0.5,
                       transform: nil))
    ctx.setStrokeColor(RGB(r: 1, g: 1, b: 1).cg(0.08))
    ctx.setLineWidth(max(1, s * 0.003))
    ctx.strokePath()

    return ctx.makeImage()
}

// MARK: - Iconset sizes

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    guard let img = drawIcon(size: px) else {
        FileHandle.standardError.write("✗ failed at \(px)px\n".data(using: .utf8)!)
        continue
    }
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: px, height: px)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let out = iconsetURL.appendingPathComponent(name)
    try png.write(to: out)
    print("✓ \(name) (\(px)×\(px))")
}

print("\nPacking AppIcon.icns…")
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["--convert", "icns", iconsetURL.path, "--output", icnsURL.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus == 0 {
    print("✓ \(icnsURL.path)")
} else {
    FileHandle.standardError.write("iconutil failed with status \(task.terminationStatus)\n".data(using: .utf8)!)
    exit(Int32(task.terminationStatus))
}

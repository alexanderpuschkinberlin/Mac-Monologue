// Generates Resources/AppIcon.icns.
//
// A generic-icon app looks broken rather than minimal, and a plain geometric
// mark costs five minutes. Run with: swift tools/make-icon.swift
import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icons sit inset from the canvas edge.
    let margin = size * 0.085
    let body = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = body.width * 0.2237   // the macOS squircle, near enough

    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(
        starting: NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.22, alpha: 1),
        ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
    )?.draw(in: shape, angle: -90)

    let centre = NSPoint(x: size / 2, y: size / 2)

    // Ring.
    let ringRadius = size * 0.275
    let ring = NSBezierPath(ovalIn: NSRect(
        x: centre.x - ringRadius, y: centre.y - ringRadius,
        width: ringRadius * 2, height: ringRadius * 2
    ))
    ring.lineWidth = max(1, size * 0.032)
    NSColor(calibratedWhite: 1, alpha: 0.82).setStroke()
    ring.stroke()

    // Record dot.
    let dotRadius = size * 0.155
    let dot = NSBezierPath(ovalIn: NSRect(
        x: centre.x - dotRadius, y: centre.y - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2
    ))
    NSColor(calibratedRed: 0.90, green: 0.28, blue: 0.30, alpha: 1).setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent(name))
}

print("wrote \(variants.count) sizes to \(iconset.path)")

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa

// Renders the StandYouUp app icon as a 1024×1024 PNG.
// Usage: genicon <output.png>

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS-style rounded rectangle with a little padding.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = (size - 2 * inset) * 0.2237
let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Blue vertical gradient background.
let top = NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.92, alpha: 1)
let bottom = NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.82, alpha: 1)
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// The standing-figure glyph, tinted white and centered.
let config = NSImage.SymbolConfiguration(pointSize: 640, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                           width: s.width, height: s.height))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa

// Renders a promotional screenshot of the stand-up overlay to a PNG.
// Usage: genshot <output.png>

let W: CGFloat = 1600, H: CGFloat = 1000
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "screenshot.png"

let muted = NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.36, alpha: 1)

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// Overlay background.
NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

func drawCentered(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, maxWidth: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineSpacing = 8
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.boundingRect(with: NSSize(width: maxWidth, height: 600),
                                options: [.usesLineFragmentOrigin, .usesFontLeading])
    let rect = NSRect(x: (W - maxWidth) / 2, y: centerY - bounds.height / 2, width: maxWidth, height: bounds.height)
    s.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

drawCentered("Time to stand up 🧍",
             font: .systemFont(ofSize: 66, weight: .bold), color: .white, centerY: 810, maxWidth: W - 200)
drawCentered("Step away from the screen. Tap below once you're on your feet.",
             font: .systemFont(ofSize: 28, weight: .regular),
             color: NSColor.white.withAlphaComponent(0.7), centerY: 735, maxWidth: W - 300)
drawCentered("\u{201C}We are what we think. All that we are arises with our thoughts. With our thoughts, we make the world.\u{201D}",
             font: .systemFont(ofSize: 38, weight: .light),
             color: NSColor.white.withAlphaComponent(0.92), centerY: 560, maxWidth: 1120)
drawCentered("— Dhammapada, v.1",
             font: .systemFont(ofSize: 22, weight: .medium),
             color: NSColor.white.withAlphaComponent(0.45), centerY: 455, maxWidth: W - 300)

// Buttons row.
let buttons: [(String, NSColor)] = [
    ("I'm standing up now", .systemBlue),
    ("Snooze 5 min", muted),
    ("Dismiss (Esc)", muted),
]
let btnFont = NSFont.systemFont(ofSize: 22, weight: .medium)
let spacing: CGFloat = 24
let widths = buttons.map { ($0.0 as NSString).size(withAttributes: [.font: btnFont]).width + 72 }
let totalWidth = widths.reduce(0, +) + spacing * CGFloat(buttons.count - 1)
var x = (W - totalWidth) / 2
let cy: CGFloat = 320
let h: CGFloat = 64
for (i, button) in buttons.enumerated() {
    let w = widths[i]
    let rect = NSRect(x: x, y: cy - h / 2, width: w, height: h)
    button.1.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let s = NSAttributedString(string: button.0, attributes: [
        .font: btnFont, .foregroundColor: NSColor.white, .paragraphStyle: para,
    ])
    let sz = s.size()
    s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    x += w + spacing
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render screenshot\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa

/// A borderless window that can still become key, so overlay buttons work.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension AppDelegate {

    /// Presents the full-screen break overlay on every screen.
    func showOverlay(heading: String, subtitle: String,
                     primaryTitle: String, primaryAction: Selector,
                     secondaryTitle: String, secondaryAction: Selector) {
        dismissOverlays()
        promptActive = true
        let verse = randomVerse()
        for screen in NSScreen.screens {
            overlayWindows.append(makeOverlay(on: screen, verse: verse,
                                              heading: heading, subtitle: subtitle,
                                              primaryTitle: primaryTitle, primaryAction: primaryAction,
                                              secondaryTitle: secondaryTitle, secondaryAction: secondaryAction))
        }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKeyAndOrderFront(nil)
        rebuildMenu()
    }

    private func makeOverlay(on screen: NSScreen, verse: (text: String, ref: String),
                            heading: String, subtitle: String,
                            primaryTitle: String, primaryAction: Selector,
                            secondaryTitle: String, secondaryAction: Selector) -> NSWindow {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: true)
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 0.97)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)  // legible controls on the dark overlay

        let content = NSView(frame: screen.frame)
        content.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let head = label(heading, size: 44, weight: .bold, color: .white)
        let sub = label(subtitle, size: 19, weight: .regular, color: NSColor.white.withAlphaComponent(0.7))

        let quote = label("\u{201C}\(verse.text)\u{201D}", size: 24, weight: .light,
                          color: NSColor.white.withAlphaComponent(0.92))
        quote.font = NSFont.systemFont(ofSize: 24, weight: .light)
        quote.maximumNumberOfLines = 0
        quote.preferredMaxLayoutWidth = min(760, screen.frame.width - 200)
        quote.lineBreakMode = .byWordWrapping

        let ref = label("— \(verse.ref)", size: 15, weight: .medium,
                        color: NSColor.white.withAlphaComponent(0.45))

        let primary = makeButton(primaryTitle, action: primaryAction, prominent: true)
        let secondary = makeButton(secondaryTitle, action: secondaryAction, prominent: false)
        let dismiss = makeButton("Dismiss (Esc)", action: #selector(dismissPrompt), prominent: false)
        dismiss.keyEquivalent = "\u{1b}"   // Escape — instant emergency out

        let buttons = NSStackView(views: [primary, secondary, dismiss])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        stack.addArrangedSubview(head)
        stack.addArrangedSubview(sub)
        stack.setCustomSpacing(52, after: sub)
        stack.addArrangedSubview(quote)
        stack.addArrangedSubview(ref)
        stack.setCustomSpacing(56, after: ref)
        stack.addArrangedSubview(buttons)

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: min(820, screen.frame.width - 160)),
        ])

        window.contentView = content
        window.orderFrontRegardless()
        return window
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = .center
        return l
    }

    private func makeButton(_ title: String, action: Selector, prominent: Bool) -> NSButton {
        // Flat, layer-backed buttons drawn with a constant fill. The system
        // bezel (especially the Return-key "default" button) only paints its
        // accent colour on the *key* window, so on a multi-monitor setup the
        // primary button looked blue on one screen and dark on the others.
        // Drawing the fill ourselves makes every button identical on every screen.
        let b = NSButton(title: "", target: self, action: action)
        b.isBordered = false
        b.wantsLayer = true
        let weight: NSFont.Weight = prominent ? .semibold : .medium
        let font = NSFont.systemFont(ofSize: 15, weight: weight)
        let bg = prominent
            ? NSColor.systemBlue
            : NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.36, alpha: 1.0)
        b.layer?.backgroundColor = bg.cgColor
        b.layer?.cornerRadius = 10
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: font,
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.widthAnchor.constraint(equalToConstant: ceil(textWidth) + 48).isActive = true
        if prominent { b.keyEquivalent = "\r" }
        return b
    }
}

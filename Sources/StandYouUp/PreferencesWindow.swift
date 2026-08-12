// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa
import StandYouUpCore

extension AppDelegate {

    @objc func openPreferences() {
        if prefsWindow == nil { buildPrefsWindow() }
        populatePrefsFields()
        NSApp.setActivationPolicy(.regular)   // let the settings window take focus
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.center()
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildPrefsWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 470),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "StandYouUp — Working Hours"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let intro = NSTextField(wrappingLabelWithString:
            "Reminders run only during the hours you set below. Leave every day blank to be reminded all day, every day.")
        intro.font = NSFont.boldSystemFont(ofSize: 12)
        intro.translatesAutoresizingMaskIntoConstraints = false
        intro.preferredMaxLayoutWidth = 430
        root.addArrangedSubview(intro)

        let hint = NSTextField(wrappingLabelWithString:
            "For each day, enter one or more time ranges in 24-hour format, separated by commas. Leave a day blank for a day off.\nExample:  09:00-12:30, 13:30-17:00")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 430
        root.addArrangedSubview(hint)

        dayFields = []
        for day in displayDays {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY

            let name = NSTextField(labelWithString: day.name)
            name.alignment = .right
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 90).isActive = true

            let field = NSTextField(string: "")
            field.placeholderString = "e.g. 09:00-17:00 (blank = day off)"
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
            dayFields.append(field)

            row.addArrangedSubview(name)
            row.addArrangedSubview(field)
            root.addArrangedSubview(row)
        }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPreferences))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(savePreferences))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(save)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(root)
        container.addSubview(buttons)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: root.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        window.contentView = container
        prefsWindow = window
    }

    private func populatePrefsFields() {
        let raw = UserDefaults.standard.dictionary(forKey: Keys.scheduleRaw) as? [String: String] ?? [:]
        for (i, day) in displayDays.enumerated() {
            dayFields[i].stringValue = raw["\(day.weekday)"] ?? ""
        }
    }

    @objc private func savePreferences() {
        var raw: [String: String] = [:]
        var byWeekday: [Int: [WorkSchedule.Shift]] = [:]
        for (i, day) in displayDays.enumerated() {
            let text = dayFields[i].stringValue
            do {
                byWeekday[day.weekday] = try WorkSchedule.parseShifts(text)
                raw["\(day.weekday)"] = text
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't read the hours for \(day.name)"
                alert.informativeText = "Use 24-hour times like 09:00-17:00, and separate multiple shifts with commas. Problem near: \"\(text)\""
                alert.alertStyle = .warning
                if let win = prefsWindow {
                    alert.beginSheetModal(for: win) { _ in }
                } else {
                    alert.runModal()
                }
                return
            }
        }
        workSchedule = WorkSchedule(shiftsByWeekday: byWeekday)
        UserDefaults.standard.set(raw, forKey: Keys.scheduleRaw)
        UserDefaults.standard.set(workSchedule.isActive, forKey: Keys.scheduleEnabled)
        closePrefs()
        if !isPaused { resumeScheduling() }
        rebuildMenu()
    }

    @objc private func cancelPreferences() { closePrefs() }

    private func closePrefs() {
        prefsWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)   // back to menu-bar-only
    }

    public func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === prefsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

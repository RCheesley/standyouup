// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa
import ServiceManagement
import UserNotifications
import StandYouUpCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    enum Mode { case sitting, standing }

    var statusItem: NSStatusItem!

    // Once a second: checks whether a prompt or shift change is due, and
    // refreshes the menu-bar title. Deadlines are compared against the wall
    // clock here (not left to one long timer) so they survive the Mac sleeping.
    var tickTimer: Timer?

    var mode: Mode = .sitting
    var nextPromptDate: Date?
    var promptActive = false
    var isPaused = false
    var promptIsManual = false    // the prompt on screen came from the menu, not the schedule
    var waitingForShift = false   // off the clock, parked until the next shift starts
    var awaySince: Date?          // set while the Mac or its displays are asleep

    var overlayWindows: [NSWindow] = []

    // Working-hours schedule (pure logic lives in StandYouUpCore).
    var workSchedule = WorkSchedule()

    // Preferences window
    var prefsWindow: NSWindow?
    var dayFields: [NSTextField] = []

    var sitInterval: TimeInterval { TimeInterval(minutes(Keys.sitMinutes, fallback: 60) * 60) }
    var standInterval: TimeInterval { TimeInterval(minutes(Keys.standMinutes, fallback: 15) * 60) }

    /// True when a schedule is set and we're currently off the clock.
    var isOffHours: Bool { workSchedule.isActive && !workSchedule.isWorking(at: Date()) }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        setupMainMenu()   // provides the Edit menu so Cut/Copy/Paste work in text fields
        loadSchedule()
        setupStatusItem()
        resumeScheduling()
        observeSleepAndWake()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    // MARK: Main menu (enables keyboard Cut/Copy/Paste in text fields)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit StandYouUp",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        setStatus(symbol: "chair.fill", text: "–")
        rebuildMenu()
    }

    /// Sets a monochrome template icon (auto-tinted white/black by the menu bar)
    /// plus the countdown text, so it's always visible over any wallpaper.
    private func setStatus(symbol: String, text: String) {
        guard let button = statusItem.button else { return }
        let shown = UserDefaults.standard.bool(forKey: Keys.compactMenuBar) ? "" : text
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: text) {
            img.isTemplate = true
            button.image = img
            button.title = shown.isEmpty ? "" : " \(shown)"
        } else {
            button.image = nil
            button.title = shown
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let rests = NSMenuItem(title: "Rests today: \(restsToday())", action: nil, keyEquivalent: "")
        rests.isEnabled = false
        menu.addItem(rests)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Stand up now", action: #selector(standNow), keyEquivalent: "s").target = self
        menu.addItem(withTitle: isPaused ? "Resume reminders" : "Pause reminders",
                     action: #selector(togglePause), keyEquivalent: "").target = self

        menu.addItem(.separator())

        addPresetSubmenu(to: menu, title: "Sit for", key: Keys.sitMinutes, fallback: 60,
                         options: [30, 45, 60, 90], action: #selector(setSit(_:)))
        addPresetSubmenu(to: menu, title: "Stand for", key: Keys.standMinutes, fallback: 15,
                         options: [5, 10, 15, 20, 30], action: #selector(setStand(_:)))

        let hoursItem = NSMenuItem(title: workSchedule.isActive ? "Working hours… (on)" : "Working hours…",
                                   action: #selector(openPreferences), keyEquivalent: "")
        hoursItem.target = self
        menu.addItem(hoursItem)

        menu.addItem(.separator())

        // Sound picker
        let soundParent = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        let off = NSMenuItem(title: "Off", action: #selector(setSound(_:)), keyEquivalent: "")
        off.target = self
        off.state = (currentSoundName() == "Off") ? .on : .off
        soundMenu.addItem(off)
        soundMenu.addItem(.separator())
        for name in availableSounds {
            let it = NSMenuItem(title: name, action: #selector(setSound(_:)), keyEquivalent: "")
            it.target = self
            it.state = (currentSoundName() == name) ? .on : .off
            soundMenu.addItem(it)
        }
        soundMenu.addItem(.separator())
        let test = NSMenuItem(title: "Test sound", action: #selector(testSound), keyEquivalent: "")
        test.target = self
        soundMenu.addItem(test)
        soundParent.submenu = soundMenu
        menu.addItem(soundParent)

        // Volume picker
        let volParent = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        let volMenu = NSMenu()
        for pct in [25, 50, 75, 100] {
            let it = NSMenuItem(title: "\(pct)%", action: #selector(setVolume(_:)), keyEquivalent: "")
            it.target = self
            it.tag = pct
            it.state = (currentVolume() == pct) ? .on : .off
            volMenu.addItem(it)
        }
        volParent.submenu = volMenu
        menu.addItem(volParent)

        menu.addItem(.separator())

        let compactItem = NSMenuItem(title: "Compact menu bar (icon only)", action: #selector(toggleCompact), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = UserDefaults.standard.bool(forKey: Keys.compactMenuBar) ? .on : .off
        menu.addItem(compactItem)

        let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StandYouUp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    private func addPresetSubmenu(to menu: NSMenu, title: String, key: String, fallback: Int,
                                  options: [Int], action: Selector) {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in options {
            let it = NSMenuItem(title: "\(m) minutes", action: action, keyEquivalent: "")
            it.target = self
            it.tag = m
            it.state = (minutes(key, fallback: fallback) == m) ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    private func statusText() -> String {
        if isPaused { return "Paused" }
        if promptActive { return mode == .sitting ? "Time to stand up" : "Time to sit down" }
        if isOffHours {
            if let next = workSchedule.nextShiftStart(after: Date()) {
                return "Off — next shift \(shiftTimeString(next))"
            }
            return "Off — no working hours set"
        }
        guard let next = nextPromptDate else { return "—" }
        return mode == .sitting
            ? "Stand up in \(humanShort(next.timeIntervalSinceNow))"
            : "Sit down in \(humanShort(next.timeIntervalSinceNow))"
    }

    // MARK: Phase scheduling

    /// Entry point for (re)starting reminders. If we're off the clock, wait for
    /// the next shift instead of nagging.
    func resumeScheduling() {
        guard !isPaused else { return }
        if isOffHours { waitForNextShift() } else { beginSitting() }
    }

    /// Park until the next configured shift starts. `advanceSchedule` restarts
    /// the cycle when it does.
    private func waitForNextShift() {
        mode = .sitting
        nextPromptDate = nil
        waitingForShift = true
        rebuildMenu()
    }

    private func beginSitting() {
        mode = .sitting
        schedulePrompt(after: sitInterval)
    }

    private func beginStanding() {
        mode = .standing
        schedulePrompt(after: standInterval)
    }

    private func schedulePrompt(after interval: TimeInterval) {
        promptActive = false
        waitingForShift = false
        guard !isPaused else { nextPromptDate = nil; return }
        nextPromptDate = Date().addingTimeInterval(interval)
        rebuildMenu()
    }

    private func firePrompt() {
        promptIsManual = false
        mode == .sitting ? presentStandPrompt() : presentSitPrompt()
    }

    /// Called every second. Moves the cycle on when a shift starts or ends, or
    /// when the next prompt is due.
    private func advanceSchedule() {
        guard !isPaused, awaySince == nil else { return }
        if isOffHours {
            if promptActive {
                // A prompt you asked for from the menu stays up; a scheduled one
                // left on screen when the shift ended is cleared.
                guard !promptIsManual else { return }
                dismissOverlays()
                waitForNextShift()
            } else if !waitingForShift {
                waitForNextShift()
            }
        } else if waitingForShift {
            beginSitting()   // the shift has started
        } else if !promptActive, let due = nextPromptDate, Date() >= due {
            firePrompt()
        }
    }

    // MARK: Sleep & wake

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.userWentAway()
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.userCameBack()
            }
        }
    }

    private func userWentAway() {
        if awaySince == nil { awaySince = Date() }
    }

    /// Time with the Mac or its displays asleep counts as time away from the
    /// desk. If it was at least a stand-length break, start a fresh sit period.
    private func userCameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        guard !isPaused, Date().timeIntervalSince(since) >= standInterval else { return }
        if promptActive {
            if mode == .sitting { incrementRestCount() }   // left while asked to stand: a rest
            dismissOverlays()
        }
        resumeScheduling()
    }

    private func tick() {
        advanceSchedule()
        if isPaused {
            setStatus(symbol: "pause.circle", text: "Paused")
        } else if promptActive {
            if mode == .sitting { setStatus(symbol: "figure.stand", text: "Stand up!") }
            else { setStatus(symbol: "chair.fill", text: "Sit down!") }
        } else if isOffHours {
            setStatus(symbol: "moon.zzz", text: "Off")
        } else if let next = nextPromptDate {
            let symbol = mode == .sitting ? "chair.fill" : "figure.stand"
            setStatus(symbol: symbol, text: humanShort(next.timeIntervalSinceNow))
        }
    }

    // MARK: Prompts

    @objc private func standNow() {
        promptIsManual = true
        presentStandPrompt()
    }

    private func presentStandPrompt() {
        chime()
        notify(title: "Time to stand up 🧍", body: "Step away from the screen for a bit.")
        showOverlay(
            heading: "Time to stand up 🧍",
            subtitle: "Step away from the screen. Tap below once you're on your feet.",
            primaryTitle: "I'm standing up now",
            primaryAction: #selector(confirmStanding),
            secondaryTitle: "Snooze 5 min",
            secondaryAction: #selector(snooze))
    }

    private func presentSitPrompt() {
        chime()
        notify(title: "You can sit down now 🪑", body: "Nicely done — settle back in.")
        showOverlay(
            heading: "You can sit down now 🪑",
            subtitle: "Nicely done. Settle back in whenever you're ready.",
            primaryTitle: "I'm sitting down now",
            primaryAction: #selector(confirmSitting),
            secondaryTitle: "Stand 5 more min",
            secondaryAction: #selector(standFiveMore))
    }

    @objc private func confirmStanding() {
        incrementRestCount()  // count this as a rest taken today
        dismissOverlays()
        beginStanding()       // wait stand-length, then prompt to sit
    }

    @objc private func confirmSitting() {
        dismissOverlays()
        beginSitting()        // wait sit-length, then prompt to stand
    }

    @objc private func snooze() {
        dismissOverlays()
        mode = .sitting
        schedulePrompt(after: 5 * 60)   // remind me to stand again in 5 min
    }

    @objc private func standFiveMore() {
        dismissOverlays()
        mode = .standing
        schedulePrompt(after: 5 * 60)   // keep standing, remind to sit in 5 min
    }

    /// Emergency out: clear the overlay instantly and don't nag again until the
    /// next normal interval for the current posture (so it won't reappear mid-call).
    @objc func dismissPrompt() {
        dismissOverlays()
        schedulePrompt(after: mode == .sitting ? sitInterval : standInterval)
    }

    func dismissOverlays() {
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()
        promptActive = false
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu actions

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            dismissOverlays()
            nextPromptDate = nil
        } else {
            resumeScheduling()
        }
        rebuildMenu()
    }

    @objc private func setSit(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Keys.sitMinutes)
        if !isPaused && !promptActive && mode == .sitting && !isOffHours { schedulePrompt(after: sitInterval) }
        rebuildMenu()
    }

    @objc private func setStand(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Keys.standMinutes)
        if !isPaused && !promptActive && mode == .standing && !isOffHours { schedulePrompt(after: standInterval) }
        rebuildMenu()
    }

    // MARK: Launch at login

    private func isLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("StandYouUp: login toggle failed: \(error)") }
        rebuildMenu()
    }

    // MARK: Working hours

    func loadSchedule() {
        var byWeekday: [Int: [WorkSchedule.Shift]] = [:]
        if let raw = UserDefaults.standard.dictionary(forKey: Keys.scheduleRaw) as? [String: String] {
            for (key, text) in raw {
                if let wd = Int(key), let shifts = try? WorkSchedule.parseShifts(text) {
                    byWeekday[wd] = shifts
                }
            }
        }
        workSchedule = WorkSchedule(shiftsByWeekday: byWeekday)
    }

    func shiftTimeString(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let time = f.string(from: date)
        if cal.isDateInToday(date) { return time }
        if cal.isDateInTomorrow(date) { return "tomorrow \(time)" }
        let day = DateFormatter(); day.dateFormat = "EEE"
        return "\(day.string(from: date)) \(time)"
    }

    // MARK: Chime & notifications

    private func chime() {
        let name = UserDefaults.standard.string(forKey: Keys.soundName) ?? "Glass"
        guard name != "Off" else { return }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        let vol = UserDefaults.standard.object(forKey: Keys.soundVolume) as? Int ?? 100
        sound.volume = Float(vol) / 100.0
        sound.play()
    }

    private func currentSoundName() -> String {
        UserDefaults.standard.string(forKey: Keys.soundName) ?? "Glass"
    }

    private func currentVolume() -> Int {
        UserDefaults.standard.object(forKey: Keys.soundVolume) as? Int ?? 100
    }

    @objc private func setSound(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.title, forKey: Keys.soundName)
        chime()          // preview the choice
        rebuildMenu()
    }

    @objc private func setVolume(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Keys.soundVolume)
        chime()          // preview at the new volume
        rebuildMenu()
    }

    @objc private func testSound() { chime() }

    @objc private func toggleCompact() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: Keys.compactMenuBar), forKey: Keys.compactMenuBar)
        tick()          // refresh the menu-bar item immediately
        rebuildMenu()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error { NSLog("StandYouUp: notification auth error: \(error)") }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Daily rest count

    private func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func restsToday() -> Int {
        let d = UserDefaults.standard
        return d.string(forKey: Keys.restCountDay) == today() ? d.integer(forKey: Keys.restCount) : 0
    }

    private func incrementRestCount() {
        let d = UserDefaults.standard
        d.set(restsToday() + 1, forKey: Keys.restCount)
        d.set(today(), forKey: Keys.restCountDay)
    }

    // MARK: Helpers

    func humanShort(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 60 ? "\(s / 60)m" : "\(s)s"
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Cocoa
import ServiceManagement
import UserNotifications
import StandYouUpCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    var statusItem: NSStatusItem!

    // Once a second: checks whether a prompt or shift change is due, and
    // refreshes the menu-bar title. Deadlines are compared against the wall
    // clock here (not left to one long timer) so they survive the Mac sleeping.
    var tickTimer: Timer?

    /// The sit/stand cycle itself: what phase we're in, when the next prompt is
    /// due, pauses, working hours and sleep. The logic lives in StandYouUpCore,
    /// where it is unit-tested; this class draws what it says.
    var cycle = ReminderCycle(sitInterval: 60 * 60, standInterval: 15 * 60)

    // Read-only views of the cycle, for the menu, the overlay and the settings window.
    var mode: ReminderCycle.Mode { cycle.mode }
    var nextPromptDate: Date? { cycle.nextPromptDate }
    var promptActive: Bool { cycle.promptActive }
    var isPaused: Bool { cycle.isPaused }
    var pauseUntil: Date? { cycle.pauseUntil }

    var overlayWindows: [NSWindow] = []

    /// One identifier for every prompt notification, so each replaces the last.
    private let promptNotificationID = "standyouup.prompt"

    /// UserNotifications needs an app bundle; without one (e.g. `swift run`) it crashes.
    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    // Working-hours schedule, held by the cycle.
    var workSchedule: WorkSchedule {
        get { cycle.schedule }
        set { cycle.schedule = newValue }
    }

    // Preferences window
    var prefsWindow: NSWindow?
    var dayFields: [NSTextField] = []

    // Menu items whose text depends on the moment the menu is opened.
    var statusMenuItem: NSMenuItem?
    var restsMenuItem: NSMenuItem?
    var postureMenuItem: NSMenuItem?

    var sitInterval: TimeInterval { TimeInterval(minutes(Keys.sitMinutes, fallback: 60) * 60) }
    var standInterval: TimeInterval { TimeInterval(minutes(Keys.standMinutes, fallback: 15) * 60) }

    /// True when a schedule is set and we're currently off the clock.
    var isOffHours: Bool { cycle.isOffHours(at: Date()) }

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

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let rests = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        rests.isEnabled = false
        menu.addItem(rests)
        restsMenuItem = rests

        menu.addItem(.separator())

        let posture = NSMenuItem(title: "", action: nil, keyEquivalent: "s")
        posture.target = self
        menu.addItem(posture)
        postureMenuItem = posture
        if isPaused {
            menu.addItem(withTitle: "Resume reminders",
                         action: #selector(togglePause), keyEquivalent: "").target = self
        } else {
            let pauseParent = NSMenuItem(title: "Pause reminders", action: nil, keyEquivalent: "")
            let pauseMenu = NSMenu()
            for (title, mins) in [("For 30 minutes", 30), ("For 1 hour", 60), ("For 2 hours", 120)] {
                let it = NSMenuItem(title: title, action: #selector(pauseFor(_:)), keyEquivalent: "")
                it.target = self
                it.tag = mins
                pauseMenu.addItem(it)
            }
            let tomorrow = NSMenuItem(title: "Until tomorrow", action: #selector(pauseUntilTomorrow), keyEquivalent: "")
            tomorrow.target = self
            pauseMenu.addItem(tomorrow)
            pauseMenu.addItem(.separator())
            let open = NSMenuItem(title: "Until I resume", action: #selector(togglePause), keyEquivalent: "")
            open.target = self
            pauseMenu.addItem(open)
            pauseParent.submenu = pauseMenu
            menu.addItem(pauseParent)
        }

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

        menu.delegate = self
        refreshLiveMenuItems()
        statusItem.menu = menu
    }

    /// Called just before the menu opens, so the countdown, rest count and the
    /// stand/sit item are never stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLiveMenuItems()
    }

    private func refreshLiveMenuItems() {
        statusMenuItem?.title = statusText()
        restsMenuItem?.title = "Rests today: \(restsToday())"
        // Offer the opposite of what you're doing now.
        if mode == .standing {
            postureMenuItem?.title = "Sit down now"
            postureMenuItem?.action = #selector(sitNow)
        } else {
            postureMenuItem?.title = "Stand up now"
            postureMenuItem?.action = #selector(standNow)
        }
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
        if isPaused {
            guard let until = pauseUntil else { return "Paused" }
            // A pause to midnight reads better as "tomorrow" than as "tomorrow 00:00".
            if Calendar.current.startOfDay(for: until) == until { return "Paused until tomorrow" }
            return "Paused until \(shiftTimeString(until))"
        }
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

    /// Runs one step of the cycle with the current settings and time, carries
    /// out what it asks for, and refreshes the menu if anything changed.
    private func drive(_ step: (inout ReminderCycle, Date) -> [ReminderCycle.Effect]) {
        cycle.sitInterval = sitInterval
        cycle.standInterval = standInterval
        let before = cycle
        let effects = step(&cycle, Date())
        for effect in effects {
            switch effect {
            case .countRest: incrementRestCount()
            case .dismissPrompt: dismissOverlays()
            case .showStandPrompt: presentStandPrompt()
            case .showSitPrompt: presentSitPrompt()
            }
        }
        if cycle != before || !effects.isEmpty { rebuildMenu() }
    }

    /// Entry point for (re)starting reminders. If we're off the clock, the cycle
    /// waits for the next shift instead of nagging.
    func resumeScheduling() {
        drive { cycle, now in cycle.start(now: now); return [] }
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
        drive { cycle, now in cycle.wentAway(now: now); return [] }
    }

    /// Time with the Mac or its displays asleep counts as time away from the
    /// desk. If it was at least a stand-length break, start a fresh sit period.
    private func userCameBack() {
        drive { cycle, now in cycle.cameBack(now: now) }
    }

    private func tick() {
        drive { cycle, now in cycle.tick(now: now) }
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
        drive { cycle, now in cycle.standNow(now: now) }
    }

    private func presentStandPrompt() {
        chime()
        showOverlay(
            heading: "Time to stand up 🧍",
            subtitle: "Step away from the screen. Tap below once you're on your feet.",
            primaryTitle: "I'm standing up now",
            primaryAction: #selector(confirmStanding),
            secondaryTitle: "Snooze 5 min",
            secondaryAction: #selector(snooze))
        notify(title: "Time to stand up 🧍", body: "Step away from the screen for a bit.")
    }

    private func presentSitPrompt() {
        chime()
        showOverlay(
            heading: "You can sit down now 🪑",
            subtitle: "Nicely done. Settle back in whenever you're ready.",
            primaryTitle: "I'm sitting down now",
            primaryAction: #selector(confirmSitting),
            secondaryTitle: "Stand 5 more min",
            secondaryAction: #selector(standFiveMore))
        notify(title: "You can sit down now 🪑", body: "Nicely done — settle back in.")
    }

    @objc private func confirmStanding() {
        drive { cycle, now in cycle.confirmStanding(now: now) }   // counts a rest, then stand-length until the sit prompt
    }

    @objc private func confirmSitting() {
        drive { cycle, now in cycle.confirmSitting(now: now) }    // sit-length until the next stand prompt
    }

    @objc private func snooze() {
        drive { cycle, now in cycle.snooze(now: now) }            // remind me to stand again in 5 min
    }

    @objc private func standFiveMore() {
        drive { cycle, now in cycle.standFiveMore(now: now) }     // keep standing, remind to sit in 5 min
    }

    /// Emergency out: clear the overlay instantly and don't nag again until the
    /// next normal interval for the current posture (so it won't reappear mid-call).
    @objc func dismissPrompt() {
        drive { cycle, now in cycle.dismiss(now: now) }
    }

    /// Takes the overlay off every screen. The cycle decides when; this only
    /// tidies up the windows and the notification.
    func dismissOverlays() {
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()
        clearPromptNotification()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu actions

    /// Pauses reminders until `date`, or until resumed by hand when `date` is nil.
    private func pause(until date: Date?) {
        drive { cycle, now in cycle.pause(until: date, now: now) }
    }

    private func resumeReminders() {
        drive { cycle, now in cycle.resume(now: now); return [] }
    }

    @objc private func togglePause() {
        if isPaused { resumeReminders() } else { pause(until: nil) }
    }

    @objc private func pauseFor(_ sender: NSMenuItem) {
        pause(until: Date().addingTimeInterval(TimeInterval(sender.tag * 60)))
    }

    @objc private func pauseUntilTomorrow() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        pause(until: cal.date(byAdding: .day, value: 1, to: startOfToday))
    }

    @objc private func setSit(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Keys.sitMinutes)
        drive { cycle, now in cycle.restartCountdownIfIdle(in: .sitting, now: now); return [] }
        rebuildMenu()
    }

    @objc private func setStand(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Keys.standMinutes)
        drive { cycle, now in cycle.restartCountdownIfIdle(in: .standing, now: now); return [] }
        rebuildMenu()
    }

    /// Sitting back down early: clear any prompt and start a fresh sit period.
    @objc private func sitNow() {
        drive { cycle, now in cycle.sitNow(now: now) }
    }

    // MARK: Launch at login

    private func isLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLogin() {
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
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error { NSLog("StandYouUp: notification auth error: \(error)") }
        }
    }

    private func notify(title: String, body: String) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: promptNotificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Takes the prompt's notification out of Notification Centre once the
    /// prompt has been answered or dismissed.
    private func clearPromptNotification() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [promptNotificationID])
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

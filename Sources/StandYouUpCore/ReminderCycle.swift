// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Foundation

/// The sit/stand reminder cycle as a plain state machine, free of any UI so it
/// can be unit-tested. Every method takes the current time; nothing in here
/// reads the clock or starts a timer. The app calls `tick` once a second and
/// carries out the `Effect`s each call returns.
public struct ReminderCycle: Equatable {

    public enum Mode: Equatable { case sitting, standing }

    /// Something the app must do in response to a state change.
    public enum Effect: Equatable {
        case showStandPrompt
        case showSitPrompt
        case dismissPrompt
        case countRest
    }

    /// How long "Snooze" and "Stand 5 more min" put the next prompt off.
    public static let snoozeInterval: TimeInterval = 5 * 60

    /// How long a prompt ignores its answer buttons after appearing, so a key
    /// press or click already on its way can't answer it unseen.
    public static let settleInterval: TimeInterval = 1

    // MARK: Settings (set by the app)

    public var sitInterval: TimeInterval
    public var standInterval: TimeInterval
    public var schedule: WorkSchedule
    public var calendar: Calendar

    // MARK: State

    public private(set) var mode: Mode = .sitting
    /// When the next prompt is due; nil while paused, waiting for a shift, or
    /// (after a pause) until the cycle restarts.
    public private(set) var nextPromptDate: Date?
    public private(set) var promptActive = false
    /// The prompt on screen was asked for from the menu, not raised by the schedule.
    public private(set) var promptIsManual = false
    public private(set) var promptShownAt: Date?
    public private(set) var isPaused = false
    /// When a timed pause ends; nil means until resumed by hand.
    public private(set) var pauseUntil: Date?
    /// Off the clock, parked until the next shift starts.
    public private(set) var waitingForShift = false
    /// Set while the Mac or its displays are asleep.
    public private(set) var awaySince: Date?

    public init(sitInterval: TimeInterval, standInterval: TimeInterval,
                schedule: WorkSchedule = WorkSchedule(), calendar: Calendar = .current) {
        self.sitInterval = sitInterval
        self.standInterval = standInterval
        self.schedule = schedule
        self.calendar = calendar
    }

    // MARK: Queries

    /// True when working hours are set and `now` is outside them.
    public func isOffHours(at now: Date) -> Bool {
        schedule.isActive && !schedule.isWorking(at: now, calendar: calendar)
    }

    /// False for the first moment after a prompt appears.
    public func promptIsSettled(at now: Date) -> Bool {
        guard let shown = promptShownAt else { return true }
        return now.timeIntervalSince(shown) >= ReminderCycle.settleInterval
    }

    // MARK: Starting and ticking

    /// (Re)starts the cycle: a fresh sit period, or a wait for the next shift
    /// when off the clock. Does nothing while paused.
    public mutating func start(now: Date) {
        guard !isPaused else { return }
        if isOffHours(at: now) { waitForNextShift() } else { beginSitting(now: now) }
    }

    /// Call once a second. Ends a timed pause, follows shift boundaries, and
    /// raises the next prompt when it is due.
    public mutating func tick(now: Date) -> [Effect] {
        if isPaused, let until = pauseUntil, now >= until { resume(now: now) }
        guard !isPaused, awaySince == nil else { return [] }
        if isOffHours(at: now) {
            if promptActive {
                // A prompt asked for from the menu stays up; a scheduled one left
                // on screen when the shift ended is cleared.
                guard !promptIsManual else { return [] }
                let effects = clearPrompt()
                waitForNextShift()
                return effects
            }
            if !waitingForShift { waitForNextShift() }
            return []
        }
        if waitingForShift {
            beginSitting(now: now)   // the shift has started
            return []
        }
        if !promptActive, let due = nextPromptDate, now >= due {
            return present(manual: false, now: now)
        }
        return []
    }

    // MARK: Menu actions

    /// "Stand up now": raise the stand prompt straight away.
    public mutating func standNow(now: Date) -> [Effect] {
        mode = .sitting
        return present(manual: true, now: now)
    }

    /// "Sit down now": clear any prompt and start a fresh sit period.
    public mutating func sitNow(now: Date) -> [Effect] {
        let effects = clearPrompt()
        beginSitting(now: now)
        return effects
    }

    /// Pauses until `until`, or until resumed by hand when `until` is nil.
    public mutating func pause(until: Date?, now: Date) -> [Effect] {
        isPaused = true
        pauseUntil = until
        nextPromptDate = nil
        return clearPrompt()
    }

    public mutating func resume(now: Date) {
        isPaused = false
        pauseUntil = nil
        start(now: now)
    }

    /// After the sit or stand length changes: restart the countdown for `mode`
    /// if that is the phase quietly counting down right now.
    public mutating func restartCountdownIfIdle(in changed: Mode, now: Date) {
        guard !isPaused, !promptActive, mode == changed, !isOffHours(at: now) else { return }
        schedulePrompt(after: changed == .sitting ? sitInterval : standInterval, now: now)
    }

    // MARK: Prompt answers

    public mutating func confirmStanding(now: Date) -> [Effect] {
        guard promptIsSettled(at: now) else { return [] }
        let effects = [Effect.countRest] + clearPrompt()
        mode = .standing
        schedulePrompt(after: standInterval, now: now)
        return effects
    }

    public mutating func confirmSitting(now: Date) -> [Effect] {
        guard promptIsSettled(at: now) else { return [] }
        let effects = clearPrompt()
        beginSitting(now: now)
        return effects
    }

    /// "Snooze 5 min": stay sitting and ask again shortly.
    public mutating func snooze(now: Date) -> [Effect] {
        guard promptIsSettled(at: now) else { return [] }
        let effects = clearPrompt()
        mode = .sitting
        schedulePrompt(after: ReminderCycle.snoozeInterval, now: now)
        return effects
    }

    /// "Stand 5 more min": stay standing and ask again shortly.
    public mutating func standFiveMore(now: Date) -> [Effect] {
        guard promptIsSettled(at: now) else { return [] }
        let effects = clearPrompt()
        mode = .standing
        schedulePrompt(after: ReminderCycle.snoozeInterval, now: now)
        return effects
    }

    /// The emergency exit (Esc): clear the prompt at once and don't ask again
    /// until a full interval for the current posture has passed.
    public mutating func dismiss(now: Date) -> [Effect] {
        let effects = clearPrompt()
        schedulePrompt(after: mode == .sitting ? sitInterval : standInterval, now: now)
        return effects
    }

    // MARK: Sleep and wake

    public mutating func wentAway(now: Date) {
        if awaySince == nil { awaySince = now }
    }

    /// Time with the Mac or its displays asleep counts as time away from the
    /// desk. If it was at least a stand-length break, start a fresh sit period.
    public mutating func cameBack(now: Date) -> [Effect] {
        guard let since = awaySince else { return [] }
        awaySince = nil
        guard !isPaused, now.timeIntervalSince(since) >= standInterval else { return [] }
        var effects: [Effect] = []
        if promptActive {
            if mode == .sitting { effects.append(.countRest) }   // left while asked to stand: a rest
            effects += clearPrompt()
        }
        start(now: now)
        return effects
    }

    // MARK: Internals

    private mutating func waitForNextShift() {
        mode = .sitting
        nextPromptDate = nil
        waitingForShift = true
    }

    private mutating func beginSitting(now: Date) {
        mode = .sitting
        schedulePrompt(after: sitInterval, now: now)
    }

    private mutating func schedulePrompt(after interval: TimeInterval, now: Date) {
        waitingForShift = false
        guard !isPaused else { nextPromptDate = nil; return }
        nextPromptDate = now.addingTimeInterval(interval)
    }

    private mutating func present(manual: Bool, now: Date) -> [Effect] {
        promptIsManual = manual
        promptActive = true
        promptShownAt = now
        return [mode == .sitting ? .showStandPrompt : .showSitPrompt]
    }

    private mutating func clearPrompt() -> [Effect] {
        guard promptActive else { return [] }
        promptActive = false
        promptIsManual = false
        promptShownAt = nil
        return [.dismissPrompt]
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import XCTest
@testable import StandYouUpCore

final class ReminderCycleTests: XCTestCase {

    private let sit: TimeInterval = 60 * 60
    private let stand: TimeInterval = 15 * 60

    // A fixed UTC Gregorian calendar so results don't depend on the CI timezone.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-08-10 is a Monday.
    private func monday(_ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                      year: 2026, month: 8, day: 10, hour: h, minute: mi, second: s))!
    }

    private func cycle(schedule: WorkSchedule = WorkSchedule()) -> ReminderCycle {
        ReminderCycle(sitInterval: sit, standInterval: stand, schedule: schedule, calendar: cal)
    }

    /// Monday (weekday 2) 09:00–17:00 only.
    private func officeHours() throws -> WorkSchedule {
        WorkSchedule(shiftsByWeekday: [2: try WorkSchedule.parseShifts("09:00-17:00")])
    }

    // MARK: The basic cycle

    func testStartBeginsASitPeriod() {
        var c = cycle()
        c.start(now: monday(10, 0))
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(11, 0))
        XCTAssertFalse(c.promptActive)
    }

    func testStandPromptAppearsWhenDueAndNotBefore() {
        var c = cycle()
        c.start(now: monday(10, 0))
        XCTAssertEqual(c.tick(now: monday(10, 59, 59)), [])
        XCTAssertEqual(c.tick(now: monday(11, 0)), [.showStandPrompt])
        XCTAssertTrue(c.promptActive)
        XCTAssertEqual(c.tick(now: monday(11, 0, 1)), [])           // not raised twice
    }

    func testFullCycleSitStandSit() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        XCTAssertEqual(c.confirmStanding(now: monday(11, 1)), [.countRest, .dismissPrompt])
        XCTAssertEqual(c.mode, .standing)
        XCTAssertEqual(c.nextPromptDate, monday(11, 16))
        XCTAssertEqual(c.tick(now: monday(11, 16)), [.showSitPrompt])
        XCTAssertEqual(c.confirmSitting(now: monday(11, 17)), [.dismissPrompt])
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(12, 17))
    }

    // MARK: Answering a prompt

    func testAnswersAreIgnoredUntilThePromptHasSettled() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        XCTAssertEqual(c.confirmStanding(now: monday(11, 0)), [])    // same instant: a stray Return
        XCTAssertEqual(c.snooze(now: monday(11, 0)), [])
        XCTAssertTrue(c.promptActive)
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.confirmStanding(now: monday(11, 0, 1)), [.countRest, .dismissPrompt])
    }

    func testDismissWorksStraightAwayAndWaitsAFullInterval() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        XCTAssertEqual(c.dismiss(now: monday(11, 0)), [.dismissPrompt])
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(12, 0))
    }

    func testSnoozeAsksAgainInFiveMinutes() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        XCTAssertEqual(c.snooze(now: monday(11, 1)), [.dismissPrompt])
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(11, 6))
        XCTAssertEqual(c.tick(now: monday(11, 6)), [.showStandPrompt])
    }

    func testStandFiveMoreKeepsStanding() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        _ = c.confirmStanding(now: monday(11, 1))
        _ = c.tick(now: monday(11, 16))
        XCTAssertEqual(c.standFiveMore(now: monday(11, 17)), [.dismissPrompt])
        XCTAssertEqual(c.mode, .standing)
        XCTAssertEqual(c.nextPromptDate, monday(11, 22))
    }

    // MARK: Menu actions

    func testStandNowRaisesAPromptAtOnce() {
        var c = cycle()
        c.start(now: monday(10, 0))
        XCTAssertEqual(c.standNow(now: monday(10, 5)), [.showStandPrompt])
        XCTAssertTrue(c.promptActive)
        XCTAssertTrue(c.promptIsManual)
    }

    func testSitNowWhileStandingStartsAFreshSitPeriod() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        _ = c.confirmStanding(now: monday(11, 1))
        XCTAssertEqual(c.sitNow(now: monday(11, 5)), [])             // no prompt on screen to clear
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(12, 5))
    }

    func testChangingTheSitLengthRestartsTheCountdownOnlyWhileSitting() {
        var c = cycle()
        c.start(now: monday(10, 0))
        c.sitInterval = 30 * 60
        c.restartCountdownIfIdle(in: .sitting, now: monday(10, 10))
        XCTAssertEqual(c.nextPromptDate, monday(10, 40))
        c.restartCountdownIfIdle(in: .standing, now: monday(10, 20))  // not standing: no change
        XCTAssertEqual(c.nextPromptDate, monday(10, 40))
    }

    // MARK: Pausing

    func testOpenEndedPauseStopsPromptsUntilResumed() {
        var c = cycle()
        c.start(now: monday(10, 0))
        XCTAssertEqual(c.pause(until: nil, now: monday(10, 30)), [])
        XCTAssertNil(c.nextPromptDate)
        XCTAssertEqual(c.tick(now: monday(13, 0)), [])
        XCTAssertTrue(c.isPaused)
        c.resume(now: monday(13, 0))
        XCTAssertFalse(c.isPaused)
        XCTAssertEqual(c.nextPromptDate, monday(14, 0))
    }

    func testTimedPauseEndsByItself() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.pause(until: monday(11, 0), now: monday(10, 30))
        XCTAssertEqual(c.tick(now: monday(10, 59)), [])
        XCTAssertTrue(c.isPaused)
        XCTAssertEqual(c.tick(now: monday(11, 0)), [])
        XCTAssertFalse(c.isPaused)
        XCTAssertNil(c.pauseUntil)
        XCTAssertEqual(c.nextPromptDate, monday(12, 0))               // a fresh sit period
    }

    func testPausingClearsAPromptOnScreen() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        XCTAssertEqual(c.pause(until: nil, now: monday(11, 0)), [.dismissPrompt])
        XCTAssertFalse(c.promptActive)
    }

    // MARK: Working hours

    func testStartingOutsideWorkingHoursWaitsForTheShift() throws {
        var c = cycle(schedule: try officeHours())
        c.start(now: monday(7, 0))
        XCTAssertTrue(c.waitingForShift)
        XCTAssertNil(c.nextPromptDate)
        XCTAssertEqual(c.tick(now: monday(8, 59)), [])
        XCTAssertTrue(c.waitingForShift)
        XCTAssertEqual(c.tick(now: monday(9, 0)), [])
        XCTAssertFalse(c.waitingForShift)
        XCTAssertEqual(c.nextPromptDate, monday(10, 0))               // sit period starts with the shift
    }

    func testTheCycleStopsWhenTheShiftEnds() throws {
        var c = cycle(schedule: try officeHours())
        c.start(now: monday(16, 30))
        XCTAssertEqual(c.nextPromptDate, monday(17, 30))
        XCTAssertEqual(c.tick(now: monday(17, 0)), [])
        XCTAssertTrue(c.waitingForShift)
        XCTAssertNil(c.nextPromptDate)
        XCTAssertEqual(c.tick(now: monday(17, 30)), [])               // the old deadline no longer fires
    }

    func testAScheduledPromptIsClearedWhenTheShiftEnds() throws {
        var c = cycle(schedule: try officeHours())
        c.start(now: monday(15, 58))
        XCTAssertEqual(c.tick(now: monday(16, 58)), [.showStandPrompt])
        XCTAssertEqual(c.tick(now: monday(17, 0)), [.dismissPrompt])
        XCTAssertFalse(c.promptActive)
        XCTAssertTrue(c.waitingForShift)
    }

    func testAPromptAskedForOutsideWorkingHoursStaysUp() throws {
        var c = cycle(schedule: try officeHours())
        c.start(now: monday(19, 0))
        XCTAssertEqual(c.standNow(now: monday(19, 5)), [.showStandPrompt])
        XCTAssertEqual(c.tick(now: monday(19, 6)), [])
        XCTAssertTrue(c.promptActive)
        // Once answered, the cycle goes back to waiting for the next shift.
        XCTAssertEqual(c.confirmStanding(now: monday(19, 7)), [.countRest, .dismissPrompt])
        XCTAssertEqual(c.tick(now: monday(19, 8)), [])
        XCTAssertTrue(c.waitingForShift)
        XCTAssertNil(c.nextPromptDate)
    }

    // MARK: Sleep and wake

    func testNoPromptWhileAway() {
        var c = cycle()
        c.start(now: monday(10, 0))
        c.wentAway(now: monday(10, 55))
        XCTAssertEqual(c.tick(now: monday(11, 0)), [])
        XCTAssertFalse(c.promptActive)
    }

    func testAShortAbsenceCarriesOnWhereItLeftOff() {
        var c = cycle()
        c.start(now: monday(10, 0))
        c.wentAway(now: monday(10, 55))
        XCTAssertEqual(c.cameBack(now: monday(11, 5)), [])            // ten minutes: under the stand length
        XCTAssertEqual(c.nextPromptDate, monday(11, 0))
        XCTAssertEqual(c.tick(now: monday(11, 5)), [.showStandPrompt]) // overdue, so it appears now
    }

    func testALongAbsenceStartsAFreshSitPeriod() {
        var c = cycle()
        c.start(now: monday(10, 0))
        c.wentAway(now: monday(10, 30))
        XCTAssertEqual(c.cameBack(now: monday(12, 0)), [])
        XCTAssertEqual(c.mode, .sitting)
        XCTAssertEqual(c.nextPromptDate, monday(13, 0))
        XCTAssertEqual(c.tick(now: monday(12, 0)), [])
    }

    func testLeavingWhileAskedToStandCountsAsARest() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.tick(now: monday(11, 0))
        c.wentAway(now: monday(11, 1))
        XCTAssertEqual(c.cameBack(now: monday(11, 30)), [.countRest, .dismissPrompt])
        XCTAssertFalse(c.promptActive)
        XCTAssertEqual(c.nextPromptDate, monday(12, 30))
    }

    func testOnlyTheFirstSleepNotificationSetsTheStartOfTheAbsence() {
        var c = cycle()
        c.start(now: monday(10, 0))
        c.wentAway(now: monday(10, 30))   // displays sleep
        c.wentAway(now: monday(10, 45))   // then the Mac
        XCTAssertEqual(c.awaySince, monday(10, 30))
        _ = c.cameBack(now: monday(10, 50))
        XCTAssertNil(c.awaySince)
        XCTAssertEqual(c.cameBack(now: monday(10, 51)), [])           // second wake notification: nothing to do
    }

    func testComingBackWhilePausedLeavesThePauseAlone() {
        var c = cycle()
        c.start(now: monday(10, 0))
        _ = c.pause(until: nil, now: monday(10, 10))
        c.wentAway(now: monday(10, 20))
        XCTAssertEqual(c.cameBack(now: monday(12, 0)), [])
        XCTAssertTrue(c.isPaused)
        XCTAssertNil(c.nextPromptDate)
    }
}

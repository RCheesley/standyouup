// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import XCTest
@testable import StandYouUpCore

final class WorkScheduleTests: XCTestCase {

    // A fixed UTC Gregorian calendar so results don't depend on the CI timezone.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                      year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testParseTime() {
        XCTAssertEqual(WorkSchedule.parseTime("09:00"), 540)
        XCTAssertEqual(WorkSchedule.parseTime("00:00"), 0)
        XCTAssertEqual(WorkSchedule.parseTime("23:59"), 1439)
        XCTAssertNil(WorkSchedule.parseTime("24:00"))
        XCTAssertNil(WorkSchedule.parseTime("09:60"))
        XCTAssertNil(WorkSchedule.parseTime("9"))
        XCTAssertNil(WorkSchedule.parseTime("nine"))
    }

    func testParseShifts() throws {
        XCTAssertEqual(try WorkSchedule.parseShifts(""), [])
        XCTAssertEqual(try WorkSchedule.parseShifts("  "), [])
        XCTAssertEqual(try WorkSchedule.parseShifts("09:00-17:00"),
                       [.init(start: 540, end: 1020)])
        XCTAssertEqual(try WorkSchedule.parseShifts("09:00-12:30, 13:30-17:00"),
                       [.init(start: 540, end: 750), .init(start: 810, end: 1020)])
        XCTAssertThrowsError(try WorkSchedule.parseShifts("09:00"))       // missing end
        XCTAssertThrowsError(try WorkSchedule.parseShifts("17:00-09:00")) // end before start
        XCTAssertThrowsError(try WorkSchedule.parseShifts("9-5"))         // not HH:MM
    }

    func testIsActive() {
        XCTAssertFalse(WorkSchedule().isActive)
        XCTAssertFalse(WorkSchedule(shiftsByWeekday: [2: []]).isActive)
        XCTAssertTrue(WorkSchedule(shiftsByWeekday: [2: [.init(start: 540, end: 1020)]]).isActive)
    }

    // Monday (weekday 2): 09:00–12:30 and 13:30–17:00. Tuesday (3): 09:00–17:00.
    private func sampleSchedule() throws -> WorkSchedule {
        WorkSchedule(shiftsByWeekday: [
            2: try WorkSchedule.parseShifts("09:00-12:30, 13:30-17:00"),
            3: try WorkSchedule.parseShifts("09:00-17:00"),
        ])
    }

    func testIsWorking() throws {
        let s = try sampleSchedule()
        // 2026-08-10 is a Monday, 2026-08-09 a Sunday.
        XCTAssertTrue(s.isWorking(at: date(2026, 8, 10, 10, 0), calendar: cal))
        XCTAssertFalse(s.isWorking(at: date(2026, 8, 10, 12, 45), calendar: cal)) // lunch gap
        XCTAssertTrue(s.isWorking(at: date(2026, 8, 10, 13, 30), calendar: cal))
        XCTAssertFalse(s.isWorking(at: date(2026, 8, 10, 17, 0), calendar: cal))  // end exclusive
        XCTAssertFalse(s.isWorking(at: date(2026, 8, 9, 10, 0), calendar: cal))   // weekend
    }

    func testNextShiftStart() throws {
        let s = try sampleSchedule()
        XCTAssertEqual(s.nextShiftStart(after: date(2026, 8, 10, 12, 45), calendar: cal),
                       date(2026, 8, 10, 13, 30))                                  // → afternoon
        XCTAssertEqual(s.nextShiftStart(after: date(2026, 8, 10, 17, 30), calendar: cal),
                       date(2026, 8, 11, 9, 0))                                    // → next day
        XCTAssertEqual(s.nextShiftStart(after: date(2026, 8, 11, 17, 30), calendar: cal),
                       date(2026, 8, 17, 9, 0))                                    // → next Monday
    }

    func testNextShiftStartAtMidnight() throws {
        let s = WorkSchedule(shiftsByWeekday: [3: try WorkSchedule.parseShifts("00:00-08:00")])
        XCTAssertEqual(s.nextShiftStart(after: date(2026, 8, 10, 23, 0), calendar: cal),
                       date(2026, 8, 11, 0, 0))                                    // Monday night → Tuesday 00:00
    }

    // Shift starts are wall-clock times, so they must not move on the days the
    // clocks change. In the UK that's 29 March and 25 October in 2026, both Sundays.
    func testNextShiftStartOnClockChangeDays() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        func local(_ mo: Int, _ d: Int, _ h: Int) -> Date {
            london.date(from: DateComponents(year: 2026, month: mo, day: d, hour: h))!
        }
        let s = WorkSchedule(shiftsByWeekday: [1: try WorkSchedule.parseShifts("09:00-17:00")])

        let spring = try XCTUnwrap(s.nextShiftStart(after: local(3, 28, 20), calendar: london))
        XCTAssertEqual(spring, local(3, 29, 9))                                    // clocks go forward
        XCTAssertEqual(spring, date(2026, 3, 29, 8, 0))                            // 09:00 BST

        let autumn = try XCTUnwrap(s.nextShiftStart(after: local(10, 24, 20), calendar: london))
        XCTAssertEqual(autumn, local(10, 25, 9))                                   // clocks go back
        XCTAssertEqual(autumn, date(2026, 10, 25, 9, 0))                           // 09:00 GMT
    }

    func testNextShiftStartNilWhenEmpty() {
        XCTAssertNil(WorkSchedule().nextShiftStart(after: date(2026, 8, 10, 12, 0), calendar: cal))
    }
}

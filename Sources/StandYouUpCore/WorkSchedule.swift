// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Foundation

/// Thrown when a shift string can't be parsed.
public enum ScheduleError: Error, Equatable {
    case malformed(String)
}

/// A weekly working-hours schedule, free of any UI dependencies so it can be
/// unit-tested in isolation. Weekdays use `Calendar`'s numbering: Sunday = 1 …
/// Saturday = 7.
public struct WorkSchedule: Equatable {

    public struct Shift: Equatable {
        public let start: Int   // minutes from midnight
        /// Minutes from midnight on the day the shift starts (exclusive). A value
        /// above 1440 means the shift runs past midnight into the next day.
        public let end: Int
        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    public let shiftsByWeekday: [Int: [Shift]]

    public init(shiftsByWeekday: [Int: [Shift]] = [:]) {
        self.shiftsByWeekday = shiftsByWeekday
    }

    /// True when any day has hours. When false, reminders should run all day.
    public var isActive: Bool {
        shiftsByWeekday.values.contains { !$0.isEmpty }
    }

    // MARK: Parsing

    static let minutesInDay = 24 * 60

    /// Parses "HH:MM" into minutes-from-midnight, or nil if invalid. "24:00" is
    /// accepted only when `allowEndOfDay` is true, as the end of a shift.
    public static func parseTime(_ text: String, allowEndOfDay: Bool = false) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        if allowEndOfDay && h == 24 && m == 0 { return minutesInDay }
        guard (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Parses "09:00-12:30, 13:30-17:00" into ordered shifts. An empty string is
    /// a valid "day off" (returns `[]`). A shift may end at "24:00", and one whose
    /// end is earlier than its start ("22:00-06:00") runs into the next day.
    /// Throws `ScheduleError.malformed` otherwise.
    public static func parseShifts(_ text: String) throws -> [Shift] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }
        var result: [Shift] = []
        for part in trimmed.split(separator: ",") {
            let seg = part.trimmingCharacters(in: .whitespaces)
            let ends = seg.split(separator: "-")
            guard ends.count == 2,
                  let start = parseTime(String(ends[0])),
                  let end = parseTime(String(ends[1]), allowEndOfDay: true),
                  start != end else {
                throw ScheduleError.malformed(seg)
            }
            // An end earlier than the start belongs to the following day.
            result.append(Shift(start: start, end: end > start ? end : end + minutesInDay))
        }
        return result
    }

    // MARK: Queries

    /// Whether `date` falls inside a shift. Shift end is exclusive.
    public func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if (shiftsByWeekday[weekday] ?? []).contains(where: { $0.start <= minutes && minutes < $0.end }) {
            return true
        }
        // The small hours may belong to a shift that started yesterday evening.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        let sinceYesterday = minutes + WorkSchedule.minutesInDay
        return (shiftsByWeekday[yesterday] ?? []).contains { $0.start <= sinceYesterday && sinceYesterday < $0.end }
    }

    /// The soonest shift start strictly after `date`, searching up to a week
    /// ahead. Returns nil when no shifts are configured.
    public func nextShiftStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let base = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let starts = (shiftsByWeekday[weekday] ?? []).map(\.start).sorted()
            for startMinute in starts {
                // Set the wall-clock time; adding minutes to midnight is an hour
                // out on days when the clocks change.
                if let t = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60,
                                         second: 0, of: day), t > date {
                    return t
                }
            }
        }
        return nil
    }
}

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
        public let end: Int     // minutes from midnight (exclusive)
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

    /// Parses "HH:MM" into minutes-from-midnight, or nil if invalid.
    public static func parseTime(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Parses "09:00-12:30, 13:30-17:00" into ordered shifts. An empty string is
    /// a valid "day off" (returns `[]`). Throws `ScheduleError.malformed` otherwise.
    public static func parseShifts(_ text: String) throws -> [Shift] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }
        var result: [Shift] = []
        for part in trimmed.split(separator: ",") {
            let seg = part.trimmingCharacters(in: .whitespaces)
            let ends = seg.split(separator: "-")
            guard ends.count == 2,
                  let start = parseTime(String(ends[0])),
                  let end = parseTime(String(ends[1])),
                  start < end else {
                throw ScheduleError.malformed(seg)
            }
            result.append(Shift(start: start, end: end))
        }
        return result
    }

    // MARK: Queries

    /// Whether `date` falls inside a shift. Shift end is exclusive.
    public func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard let shifts = shiftsByWeekday[weekday] else { return false }
        return shifts.contains { $0.start <= minutes && minutes < $0.end }
    }

    /// The soonest shift start strictly after `date`, searching up to a week
    /// ahead. Returns nil when no shifts are configured.
    public func nextShiftStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let base = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let starts = (shiftsByWeekday[weekday] ?? []).map(\.start).sorted()
            let dayStart = calendar.startOfDay(for: day)
            for startMinute in starts {
                if let t = calendar.date(byAdding: .minute, value: startMinute, to: dayStart), t > date {
                    return t
                }
            }
        }
        return nil
    }
}

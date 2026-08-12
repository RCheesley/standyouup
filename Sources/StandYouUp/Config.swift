// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Foundation

/// UserDefaults keys. Power users can override some of these directly, e.g.
/// `defaults write uk.co.silavapi.StandYouUp sitMinutes 45`.
enum Keys {
    static let sitMinutes = "sitMinutes"       // how long you sit before being told to stand
    static let standMinutes = "standMinutes"   // how long you stand before being told to sit
    static let restCount = "restCount"         // number of rests taken today
    static let restCountDay = "restCountDay"   // yyyy-MM-dd the count belongs to
    static let soundName = "soundName"         // system sound name, or "Off"
    static let soundVolume = "soundVolume"     // 0–100 percent
    static let compactMenuBar = "compactMenuBar"   // icon only, no countdown text
    static let scheduleEnabled = "scheduleEnabled" // derived: any working hours set
    static let scheduleRaw = "scheduleRaw"     // [weekday(1–7) as String : "HH:MM-HH:MM, …"]
}

/// Built-in macOS system sounds offered as the chime.
let availableSounds = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
    "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
]

/// Weekdays in display order (Mon–Sun) paired with Calendar's numbering
/// (Sunday = 1 … Saturday = 7).
let displayDays: [(name: String, weekday: Int)] = [
    ("Monday", 2), ("Tuesday", 3), ("Wednesday", 4), ("Thursday", 5),
    ("Friday", 6), ("Saturday", 7), ("Sunday", 1),
]

/// Reads a minutes value from UserDefaults, falling back to a default.
func minutes(_ key: String, fallback: Int) -> Int {
    let v = UserDefaults.standard.integer(forKey: key)
    return v > 0 ? v : fallback
}

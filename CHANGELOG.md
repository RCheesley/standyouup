# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Releases now come as a disk image (`StandYouUp-<version>.dmg`) that you open
  and drag to your Applications folder.

### Changed
- The menu offers "Sit down now" while you're standing and "Stand up now" while
  you're sitting.
- Working hours can now run past midnight (`22:00-06:00`) or end at `24:00`.
- The menu's status line and rest count refresh every time the menu opens.

## [1.0.1] - 2026-11-28

### Changed
- The break overlay now draws on the whole Dhammapada in Max Müller's public
  domain translation, with paired verses shown together.

### Fixed
- Working hours now start and stop reminders at the shift boundaries, and a
  scheduled prompt left on screen when a shift ends is cleared.
- Reminders no longer fire late, or the moment the lid opens, after the Mac has
  been asleep. A break of at least your stand length away from the Mac starts a
  fresh sit period.
- Shift start times are no longer an hour out on days when the clocks change.
- Release downloads now run on Intel Macs as well as Apple Silicon.

## [1.0.0] - 2026-08-12

Initial public release.

### Added
- Menu-bar-only app that prompts you to stand up on a schedule.
- Full-screen stand/sit overlays across all connected displays.
- Interactive cycle: confirm standing, get reminded to sit, repeat.
- Per-day working hours with support for split shifts.
- Snooze and instant Dismiss (Esc) escape hatches.
- Chime and system notification with selectable sound and volume.
- Daily rest counter, compact menu-bar mode, and start-at-login.
- Random Dhammapada verse on each prompt.

[Unreleased]: https://github.com/rcheesley/standyouup/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/rcheesley/standyouup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/rcheesley/standyouup/releases/tag/v1.0.0

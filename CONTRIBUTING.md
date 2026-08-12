# Contributing to StandYouUp

Thanks for your interest in improving StandYouUp! This is a small, focused macOS
menu-bar app, and contributions of all sizes are welcome.

## Getting set up

You need macOS 13+ and the Xcode Command Line Tools:

```bash
xcode-select --install
git clone https://github.com/rcheesley/standyouup.git
cd standyouup
./build.sh
open StandYouUp.app
```

## Development workflow

- The **pure logic** (schedule parsing, working-hours checks) lives in
  `Sources/StandYouUpCore/` and has no AppKit dependency, so it's unit-tested.
  Add tests there for any logic change.
- The **AppKit app** lives in `Sources/StandYouUp/`, split by responsibility
  (see the "Project layout" section in the README).
- Run the tests before opening a PR:

  ```bash
  swift test
  ```

  > Note: `swift test` needs **full Xcode** (XCTest isn't in the Command Line
  > Tools). If `xcode-select -p` points at `CommandLineTools`, install Xcode and
  > run `sudo xcode-select -s /Applications/Xcode.app`. CI runs the tests on
  > every push and PR regardless.

- Keep the app buildable with just the Command Line Tools (no full Xcode project,
  no external dependencies). That's a deliberate design choice.

## Pull requests

1. Fork and create a topic branch.
2. Make your change; add or update tests in `StandYouUpCoreTests` where relevant.
3. Ensure `swift test` and `./build.sh` both succeed.
4. Open a PR describing the change and the motivation.

## Coding style

- Match the surrounding code: clear names, small methods, comments only where the
  intent isn't obvious.
- Prefer moving testable logic into `StandYouUpCore`.

## Releases & distribution

Releases are **source-first** today: users clone and run `build.sh`, which
ad-hoc signs the app.

We plan to offer **notarized binary releases** so non-developers can download and
run without Gatekeeper friction. That needs an Apple Developer ID for signing +
notarization; the `release` job in `.github/workflows/ci.yml` is scaffolded for
this and can be switched on once signing secrets are configured.

## License

By contributing, you agree that your contributions will be licensed under the
project's [GPL-3.0-or-later](LICENSE) license.

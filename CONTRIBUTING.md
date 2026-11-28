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

Each release publishes `StandYouUp-<version>.dmg`, a universal (Apple Silicon and
Intel) build in a disk image. The app is ad-hoc signed, so macOS asks people to
allow it in System Settings the first time they open it.

To cut a release:

1. Bump `VERSION` and move the "Unreleased" entries in `CHANGELOG.md` under the
   new version, in a pull request.
2. Once that is merged, publish a GitHub release with a new tag `v<version>` on
   `main` and your release notes. The tag must match `VERSION`.
3. The `release` job in `.github/workflows/ci.yml` builds the disk image and
   attaches it to that release.

Signing and notarizing with an Apple Developer ID, so the app opens with a plain
double-click, is tracked in
[#28](https://github.com/rcheesley/standyouup/issues/28).

## License

By contributing, you agree that your contributions will be licensed under the
project's [GPL-3.0-or-later](LICENSE) license.

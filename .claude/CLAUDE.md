# ELAP — Project Memory

Read at the start of every session. Keep it short and true; detail lives in the linked docs.

## What this is
ELAP fully turns a MacBook's **built-in** display off (not just dimmed) while an external
monitor is in use, and back on when needed. It ships as a Swift CLI.

## Tech stack
Swift 5.9, Swift Package Manager (ArgumentParser), macOS 13+. Display control via public
CoreGraphics APIs + the private SkyLight SPI resolved at runtime via `dlsym` — the riskiest,
most macOS-version-sensitive code.

## Commands
- Build: `swift build -c release` → `.build/release/elap`
- Run: `swift run ELAP <subcommand>`

## Versioning
- `elapVersion` (`Sources/ELAPCore/Version.swift`) is a manually-bumped semver string tied to
  `CHANGELOG.md` — `testVersionMatchesChangelog` requires a matching `[x.y.z]` entry. Bump it
  only as part of a real release, never automatically.
- `elapBuildNumber` is a separate, purely informational counter that auto-increments on
  **every** build (`swift build`/`swift run`/`swift test`, any trigger) via the SwiftPM
  prebuild plugin `Plugins/BuildNumberPlugin`, which generates `BuildInfo.swift` into
  `.build/` (gitignored, resets on `make clean`/fresh clone). Do not "fix" it if it looks like
  it's changing on its own — that's the intended behavior. `elap --version` prints
  `<elapVersion> (build <elapBuildNumber>)`.

## More docs
- [skills.md](skills.md) — conventions, display-layer safety, boundaries.
- [cli-spec.md](cli-spec.md) — full CLI specification.

## Required after every code change
- **Always run `swift test` after making any code change** and confirm all tests pass before reporting the fix as done.

## Hard boundaries
- **NEVER run `git commit`, `git push`, or `git add`** — the developer handles all git.
- **Never** strand the user with the built-in display off; always preserve a recovery path.

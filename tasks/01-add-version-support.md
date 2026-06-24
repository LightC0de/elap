# Task 01 — Add `--version` support

**Goal:** Make `elap --version` print a single-source-of-truth version string, so the
Homebrew formula's `test do` block and `brew audit` have something to probe.

**Depends on:** none

**Files to create/edit:**
- `Sources/ELAP/Version.swift` (single source of truth for the version constant)
- `Sources/ELAP/main.swift`
- `Tests/ELAPTests/ELAPTests.swift`

## Steps

1. In `Sources/ELAP/Version.swift`, define the version constant (this is the **only** file to
   edit when bumping the version in tasks 03/08):
   ```swift
   let elapVersion = "0.1.0"
   ```
2. Wire it into the root command. The `ELAPCli` `CommandConfiguration` is around
   `Sources/ELAP/main.swift:420`. Add a `version:` argument:
   ```swift
   static var configuration = CommandConfiguration(
       commandName: "elap",
       abstract: "Toggle the macOS built-in display on/off while keeping the lid open.",
       version: elapVersion,
       discussion: """
       ...keep existing discussion...
       """,
       subcommands: [List.self, Status.self, On.self, Off.self, Toggle.self, Watch.self, Daemon.self]
   )
   ```
   (ArgumentParser auto-generates the `--version` flag once `version:` is set.)
3. Add a test in `Tests/ELAPTests/ELAPTests.swift` asserting the constant is non-empty and
   matches semver, e.g.:
   ```swift
   func testVersionIsSemver() {
       XCTAssertFalse(elapVersion.isEmpty)
       XCTAssertTrue(elapVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
   }
   ```

## Acceptance criteria

- `swift run ELAP --version` prints `0.1.0`.
- `swift test` passes (run it — project rule).

## Notes / gotchas

- Keep `elapVersion` as the **only** place the version is written; later tasks (03, 08) bump
  `Sources/ELAP/Version.swift` — not `main.swift`.
- Do not hardcode the version in multiple files.

# ELAP Menu Bar App — Implementation Plan

## Context

ELAP is currently a Swift CLI that fully disables the MacBook's built-in display (a true WindowServer disconnect via private SkyLight SPI) while an external monitor is in use. This plan adds a macOS **menu bar app**: an icon in the top bar that opens a settings panel, so the built-in screen can be turned on/off in a couple of clicks — no terminal needed.

Confirmed product decisions:
- Same SwiftPM repo, new app target; the CLI keeps working unchanged.
- SwiftUI `MenuBarExtra` with `.window` style (macOS 13+, matches current platform target).
- Panel contents: on/off toggle + status, **auto-manage** switch (app-side equivalent of CLI `watch`), **launch at login**, **global hotkey** (via sindresorhus/KeyboardShortcuts — confirmed).

## Key architectural decisions & trade-offs

1. **Extract `ELAPCore` library target** shared by CLI and app. Today all 1059 lines live in `Sources/ELAP/main.swift` (executable target). Trade-off: a one-time refactor risk to CLI behavior, vs. duplicating SPI-critical code (unacceptable). CLI behavior must stay byte-identical; `.claude/cli-spec.md` remains authoritative.

2. **App never mutates displays in-process.** Confirmed in code (`main.swift:668-702`): after a process performs `CGCompleteDisplayConfiguration`, its CG display list freezes and reconfiguration callbacks stop firing — the CLI `watch` works around this with an `execv` self-restart, which an app can't do sensibly. Instead, all mutations run in a **short-lived subprocess**: the existing `elap` CLI binary bundled inside the app (`Contents/MacOS/elap`). The app's CG view stays fresh forever. Trade-off: subprocess overhead (negligible, rare events) vs. blind app after first toggle.

3. **App bundle via SwiftPM + assembly script.** SwiftPM emits a bare executable, but `LSUIElement`, a stable bundle ID, and `SMAppService` (launch at login) require a real `.app`. `scripts/make-app.sh` assembles `dist/ELAP.app`. Dev loop: `swift run ELAPApp` still works for UI iteration (MenuBarExtra works unbundled; only login-item needs the bundle). Trade-off vs. adding an Xcode project: keeps one build system, per the "same SwiftPM repo" decision; costs a small script.

4. **Safety** (hard boundary: never strand the user):
   - UI enforces the external-display guard: "turn off" is disabled with an explanation when no real external display is active.
   - On app quit while built-in is off and no external active → re-enable first.
   - All existing backstops untouched: `elap on` from Terminal, state file `~/.elap-builtin-id`, `.permanently` reverting on logout/reboot.

5. **Hotkey**: `sindresorhus/KeyboardShortcuts` (MIT), dependency of the app target only — ships a recorder UI + persistence. Fallback if it ever becomes a liability: hand-rolled Carbon `RegisterEventHotKey`.

## Phase 1 — Extract `ELAPCore`

New library target `Sources/ELAPCore/` (Foundation/CoreGraphics only). Move from `Sources/ELAP/main.swift`, making moved symbols `public`:

| New file | Content moved |
|---|---|
| `SkyLightAPI.swift` | `CGSSetDisplayEnabledFn`, `SkyLightAPI` (`load`, `setEnabled`), `DTError` |
| `Displays.swift` | `DisplayInfo`, `fetchDisplays(verbose:)`, `rawOnlineDisplaySnapshot()` |
| `StateFile.swift` | `saveBuiltInDisplayID`, `clearBuiltInDisplayID`, `loadSavedBuiltInDisplayID` |
| `Decisions.swift` | `hasActiveExternalDisplay`, `builtInDisplay(in:)`, `shouldReenableBuiltIn`, `shouldAutoDisableBuiltIn` + **new** pure `wouldStrandUser(displays:) -> Bool` |
| `SignalRecovery.swift` | `installReenableHandlers` / `removeReenableHandlers` + globals |
| `Version.swift` | `elapVersion` (moved from `Sources/ELAP/Version.swift`) |

Stays CLI-only in `Sources/ELAP/main.swift` (+ `import ELAPCore`): ArgumentParser commands, `countdownSeconds`, `waitForEnterOrTimeout`, `disableBuiltInDisplay(...)`, `printErr`, the `watch` execv machinery, `daemon`/`runLaunchctl`. **No message-string or behavior changes.**

`Package.swift`: add `.target(name: "ELAPCore")`; `ELAP` and `ELAPTests` gain the dependency.

Tests: `Tests/ELAPTests/ELAPTests.swift` adds `@testable import ELAPCore` alongside the existing `@testable import ELAP` (still needed for `waitForEnterOrTimeout`). Add unit tests for `wouldStrandUser`.

**Verify:** `swift test` passes; build release; manually diff `elap list/status/off --force/on` output against a pre-refactor binary.

## Phase 2 — App skeleton + bundle pipeline

New executable target `Sources/ELAPApp/`:
- `ELAPApp.swift` — `@main` App with `MenuBarExtra(...).menuBarExtraStyle(.window)`; icon `"display"` / `"display.slash"` driven by state; `@NSApplicationDelegateAdaptor` for the quit hook; `NSApp.setActivationPolicy(.accessory)` so the unbundled dev binary shows no Dock icon. Before SwiftUI takes over: if `CommandLine.arguments` contains `--version`, print `"ELAPApp \(elapVersion) (build \(elapBuildNumber))"` to stdout and exit(0) — mirrors the CLI's `--version` (`elapVersion`/`elapBuildNumber` from `ELAPCore`, same `BuildNumberPlugin` wired onto the `ELAPApp` target in `Package.swift`), so the installed app version can be checked from Terminal (`ELAP.app/Contents/MacOS/ELAPApp --version`) without opening the UI.
- `SettingsPanelView.swift` — the panel.

`scripts/make-app.sh` (+ Makefile target `app`; `dist/` in `.gitignore`):
- Builds `ELAPApp` and `ELAP` products; assembles `dist/ELAP.app/Contents/{MacOS,Resources}` with the CLI bundled as `MacOS/elap`.
- `Info.plist`: `CFBundleIdentifier` from `$ELAP_BUNDLE_ID` (default `com.elap.app`), `LSUIElement=true`, `CFBundleShortVersionString` extracted from `Version.swift`, `LSMinimumSystemVersion=13.0`. Bundle ID and signing identity are **env-driven, never hardcoded** (skills.md boundary).
- Codesign inner `elap` first, then the bundle; ad-hoc (`-`) by default, real identity via `$CODESIGN_IDENTITY`; never `--deep`, hardened runtime untouched.

**Verify:** `swift run ELAPApp` shows the status item and opens the panel; `./scripts/make-app.sh && open dist/ELAP.app` launches with no Dock icon; CLI still builds; `swift test`.

## Phase 3 — Toggle + status (core feature)

- `DisplayStateModel.swift` — `@MainActor ObservableObject`: published `builtInIsOn`, `hasRealExternal`, `displays`. Refreshes via `fetchDisplays()` on panel open, a 2s timer while visible, and `CGDisplayRegisterReconfigurationCallback` (registered once at launch — reliable because the app never mutates in-process).
- `ToggleHelper.swift` — locates helper binary: `Bundle.main…/Contents/MacOS/elap` → sibling of executable → `.build/{debug,release}/ELAP` (dev) → `/usr/local/bin/elap`. `async turnOff()/turnOn()` run `elap off --force` / `elap on` via `Process`, surfacing exit codes/stderr in the UI. No helper found → toggle disabled with explanation.
- Panel: status row + toggle button. Guard: when no real external is active, the off action is disabled with the reason shown. The app pre-checks the guard and only then calls `off --force` (the guard replaces the CLI countdown). Note: CLI `--timeout` auto-revert can't be reused from a subprocess (`readLine()` on non-TTY returns nil instantly); a future auto-revert would be an app-side timer.
- Panel footer: version + build number (`"\(elapVersion) (build \(elapBuildNumber))"`, same format as `--version`) — pulled forward from Phase 6 since it's a small, low-risk addition to the panel this phase already builds.

**Verify:** toggle off/on repeatedly with external attached; status stays accurate across many cycles and hot-plugs (**stale-CG acceptance test**); `elap on` from Terminal still recovers; guard blocks with no external; `swift test`.

## Phase 4 — Auto-manage + daemon-conflict warning

- `AutoManageEngine.swift` — driven by the panel switch (`@AppStorage("autoManageEnabled")`, auto-starts at launch if on). On each display-change callback/2s tick: `shouldAutoDisableBuiltIn` → helper `off --force`; `shouldReenableBuiltIn` → helper `on`. Unconditional while the switch is on (no CLI-style activation latch — the switch is explicit user intent). Serialize: never launch a second helper while one runs; re-check after completion.
- `WatchDaemonDetector.swift` — read-only check of `~/Library/LaunchAgents/com.elap.watch.plist` + `launchctl print`. If the CLI daemon runs while app auto-manage is on → warning banner ("the two will fight; run `elap daemon uninstall`"). Warn only; never mutate launchd state.

**Verify:** auto-manage on: unplug external → built-in on within ~2s; replug → off; several cycles without staleness. Install CLI daemon → warning appears. `swift test`.

## Phase 5 — Launch at login + global hotkey

- `LoginItemManager.swift` — `SMAppService.mainApp` wrapper: `isEnabled` from `.status`, register/unregister, `.requiresApproval` → hint + `openSystemSettingsLoginItems()`. Unbundled run → toggle disabled with "requires the bundled app" hint. SMAppService owns this state (not duplicated in UserDefaults).
- Hotkey: add `.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")`, product on `ELAPApp` only. `HotkeyManager.swift`: `KeyboardShortcuts.Name.toggleBuiltInDisplay`, `onKeyUp` → same guarded toggle path as the button. Panel embeds `KeyboardShortcuts.Recorder`. Persistence handled by the package.

**Verify:** `make app`, copy to `/Applications`, enable launch at login, log out/in → auto-starts. Record hotkey, trigger from another app, confirm toggle + guard. `swift test`.

## Phase 6 — Safety hardening + polish

- `applicationShouldTerminate`: if `wouldStrandUser(fetchDisplays())` → run helper `on` (bounded wait) before quitting; otherwise leave display state as the user set it.
- Icon state polish, README/CHANGELOG updates, new `.claude/app-spec.md` (cli-spec.md untouched), bump `elapVersion` with matching CHANGELOG entry (required by `testVersionMatchesChangelog`). (Version/build footer already added in Phase 3.)
- Final pass: `swift test`, `swift build -c release`, `./scripts/make-app.sh`, manual CLI regression (`list`, `status`, `off/on`, `watch`, `daemon status`).

## Risks & mitigations

- **Stale CG state** — eliminated by subprocess-mutation design; residual risk (other processes' reconfigurations) covered by 2s polling; acceptance-tested in Phase 3.
- **Guard TOCTOU** (external unplugged between check and `off --force`) — milliseconds wide; auto-manage/quit-hook/`elap on`/logout-revert all recover. Accepted.
- **SMAppService + ad-hoc signing** can be flaky — mitigate with stable bundle ID, install to /Applications, `.requiresApproval` UX, env-configurable real signing identity.
- **Refactor regression risk to CLI** — Phase 1 is isolated and verified against cli-spec.md and a pre-refactor binary diff before any app code lands.

## Critical files

- `Sources/ELAP/main.swift` — source of extraction; CLI must stay behavior-identical
- `Package.swift` — `ELAPCore` + `ELAPApp` targets, KeyboardShortcuts dependency
- `Tests/ELAPTests/ELAPTests.swift` — import migration, `wouldStrandUser` tests
- `Sources/ELAPApp/ELAPApp.swift` (new) — MenuBarExtra entry point, quit hook
- `scripts/make-app.sh` (new) — .app assembly, Info.plist, signing

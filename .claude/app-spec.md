# ELAP Menu Bar App — Spec

Companion to [cli-spec.md](cli-spec.md), which remains authoritative for CLI behavior.
Full implementation history and trade-offs: `menu-bar-app-plan.md` at the repo root.

## What it is

`ELAPApp`, a `MenuBarExtra` app (macOS 13+) that toggles the built-in display on/off from a
menu bar panel — the same capability as `elap on`/`off`, without a terminal.

## Architecture

- **`ELAPCore`** (shared library target) holds all display logic: SkyLight SPI, display
  discovery, decision functions (`hasActiveExternalDisplay`, `shouldAutoDisableBuiltIn`,
  `shouldReenableBuiltIn`, `wouldStrandUser`), state-file persistence, signal recovery,
  version. Used unchanged by both `ELAP` (CLI) and `ELAPApp`.
- **The app never mutates displays in-process.** `CGCompleteDisplayConfiguration` freezes a
  process's own CG display list after use, so a long-lived app that toggled displays directly
  would go blind to further changes. Instead every mutation runs through the bundled `elap`
  CLI binary as a short-lived subprocess (`ToggleHelper.swift`), keeping the app's own
  `CGDisplayRegisterReconfigurationCallback` reliable for its whole lifetime.
- **`dist/ELAP.app`** is assembled by `scripts/make-app.sh` (`make app`) from the SwiftPM
  build products — `ELAPApp` at `Contents/MacOS/ELAPApp`, `elap` at `Contents/MacOS/elap`.
  Bundle ID and codesigning identity are env-driven (`$ELAP_BUNDLE_ID`, `$CODESIGN_IDENTITY`),
  never hardcoded. `swift run ELAPApp` works unbundled for UI iteration; only
  launch-at-login needs the real bundle.

## Components

| File | Responsibility |
|---|---|
| `ELAPApp.swift` | `@main` App/Scene, `AppDelegate` with the quit-time safety hook |
| `SettingsPanelView.swift` | The panel: status, toggle, auto-manage switch, daemon-conflict banner, login-item toggle, hotkey recorder, version footer |
| `DisplayStateModel.swift` | `@MainActor` observable display state; refreshed by the reconfiguration callback + a 2s poll while the panel is visible |
| `ToggleHelper.swift` | Locates and runs the bundled `elap` binary as a subprocess |
| `AutoManageEngine.swift` | App-side equivalent of `elap watch`; driven by `DisplayStateModel.refresh()`, gated by `@AppStorage("autoManageEnabled")` |
| `WatchDaemonDetector.swift` | Read-only check of `~/Library/LaunchAgents/com.elap.watch.plist` + `launchctl print`; never mutates launchd state |
| `LoginItemManager.swift` | `SMAppService.mainApp` wrapper (register/unregister/status); disabled with a hint when running unbundled |
| `HotkeyManager.swift` | `sindresorhus/KeyboardShortcuts` binding (`.toggleBuiltInDisplay`) routed into the same guarded toggle path as the panel button |

## Safety

- **Off guard**: the panel's "Turn Off" only runs when a real external display is active
  (mirrors the CLI's guard); the app checks this itself since it calls `elap off --force`,
  bypassing the CLI's own interactive countdown/guard.
- **Auto-manage vs. `elap daemon`**: both would independently toggle the display if run
  together. The app only warns (`WatchDaemonDetector`) — it never touches launchd state; the
  fix is `elap daemon uninstall` or turning auto-manage off.
- **Quit-time recovery**: `AppDelegate.applicationShouldTerminate` re-enables the built-in
  display (bounded to 5s) if quitting would otherwise leave the user with no working screen
  (`wouldStrandUser`), before allowing termination.
- All CLI-level backstops (state file, SIGINT/SIGTERM handlers, `.permanently` reverting on
  logout/reboot, `elap on` from Terminal) are untouched and still apply.

## Versioning

Shares `elapVersion`/`elapBuildNumber` from `ELAPCore` with the CLI — same semver, same
`BuildNumberPlugin`. `ELAPApp --version` (or `ELAP.app/Contents/MacOS/ELAPApp --version`)
prints `<elapVersion> (build <elapBuildNumber>)`, matching the CLI's `--version`. The panel
footer shows the same string.

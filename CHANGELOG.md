# Changelog

All notable changes to ELAP are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [0.2.0] - 2026-07-09
### Added
- Menu bar app (`ELAPApp`) built on `MenuBarExtra`: toggle the built-in display on/off from
  a panel, with live status.
- Auto-manage switch in the app: app-side equivalent of `elap watch`, with a warning banner
  if the CLI's `elap daemon` is also running (the two would otherwise conflict).
- Launch at login (`SMAppService`) and a global hotkey (`KeyboardShortcuts`) to toggle the
  built-in display from anywhere.
- Quit-time safety hook: re-enables the built-in display before the app quits if doing so
  would otherwise leave the user with no working screen.
- `scripts/make-app.sh` assembles `dist/ELAP.app`, bundling the `elap` CLI inside so the app
  never mutates displays in-process — all toggles run through the bundled CLI as a subprocess.
### Changed
- Extracted `ELAPCore` library target (display discovery, decision logic, state-file
  persistence, SkyLight SPI) shared by the CLI and the new app. CLI behavior is unchanged.

## [0.1.0] - 2026-06-24
### Added
- Initial public release: `list`, `status`, `on`, `off`, `toggle`, `watch`, `daemon`.
- Built-in display disconnect via private SkyLight APIs (no SIP changes required).

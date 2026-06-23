# ELAP — Extended Laptop

A macOS CLI tool that **fully disconnects** the MacBook's built-in display from WindowServer
compositing while the lid stays open — a true GPU disconnect, not a backlight dim. Windows on
the built-in display migrate to the primary external monitor; the GPU stops rendering to it.

> ELAP is free and open source. Born from a personal itch: working with a single external
> monitor while the laptop sits open but its screen wastes GPU cycles. No existing free tool
> solved this cleanly, so this one was built from scratch.

---

## Private-API notice

ELAP uses **private SkyLight.framework APIs** (`CGSConfigureDisplayEnabled` and fallbacks)
resolved at runtime via `dlsym`. **SIP does not need to be disabled** — these calls work from
user space. The tool will break if Apple renames or removes the symbols in a future macOS
release; see [Troubleshooting](#troubleshooting).

---

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- At least one external display connected when disabling the built-in
- Xcode Command Line Tools: `xcode-select --install`

---

## Build & Install

```sh
# Build release binary
make build          # → .build/release/elap

# Install to /usr/local/bin
sudo make install   # → /usr/local/bin/elap

# Uninstall
sudo make uninstall

# Clean build artifacts
make clean
```

**Universal binary** (arm64 + x86_64):

```sh
swift build -c release --arch arm64 --arch x86_64
# output: .build/apple/Products/Release/elap
sudo cp .build/apple/Products/Release/elap /usr/local/bin/elap
```

---

## Usage

| Subcommand | Description |
|---|---|
| `list` | List all displays with IDs, resolutions, and state |
| `status` | Show whether the built-in display is enabled or disabled |
| `on` | Enable the built-in display |
| `off` | Disable the built-in display |
| `toggle` | Toggle: disable if enabled, enable if disabled |
| `watch` | Watch for display changes; auto-enable on external disconnect |
| `daemon` | Manage the background watch daemon |

### Examples

```sh
# Disable with safety countdown (requires external display)
elap off

# Disable and auto-revert after 15 seconds if not confirmed
elap off --timeout 15

# Disable immediately, skip countdown and external-display guard
elap off --force

# Re-enable the built-in display
elap on

# Toggle
elap toggle
elap toggle --timeout 10

# List all displays with verbose info
elap list --verbose

# Install the watch daemon (auto-enables built-in when external disconnects)
elap daemon install
elap daemon status
elap daemon uninstall
```

---

## Safety

- **External display required** — `elap off` refuses if no active external display is found
  (exit code 2). Override with `--force`.
- **5-second countdown** — a warning countdown runs before disabling (skipped with `--force`).
- **SIGINT / SIGTERM re-enable** — pressing Ctrl+C during or after disable re-enables the
  built-in display immediately.
- **SIGKILL cannot be caught** — if the process is killed with `SIGKILL`, the display stays
  off. Recovery:
  ```sh
  elap on
  # or, if elap itself is unavailable:
  sudo killall -KILL WindowServer
  ```
- **Logout / reboot** — `.permanently` mode reverts on logout or reboot (macOS resets display
  configuration on session end).

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error (API failure, symbol not found, etc.) |
| 2 | No active external display found |

---

## Keyboard Shortcut (Shortcuts.app)

1. Open **Shortcuts.app** → New Shortcut → Add Action → **Run Shell Script**
2. Shell: `/bin/zsh`; Script: `/usr/local/bin/elap toggle --force`
3. Assign a keyboard shortcut in the shortcut's settings

Alternatively, use **Automator** → Quick Action → Run Shell Script with the same command.

---

## How It Works

ELAP calls into the private **SkyLight.framework** (the macOS compositor layer, sitting above
CoreGraphics and below the window server). The function `CGSConfigureDisplayEnabled` removes
the display from WindowServer's compositing tree: the GPU stops rendering to it and any windows
on it migrate to the primary display.

The call is wrapped inside the standard public CoreGraphics display-configuration transaction:
`CGBeginDisplayConfiguration` → `CGSConfigureDisplayEnabled` → `CGCompleteDisplayConfiguration(.permanently)`.

The symbol is resolved at runtime via `dlsym` from a fallback list (see below), so no SkyLight
link is required and the binary degrades gracefully when a symbol is missing.

Because a disabled display **vanishes from `CGGetOnlineDisplayList`**, ELAP persists its ID to
`~/.elap-builtin-id` before disabling and recovers it via hardware probe (IDs 1–32) or the
state file when re-enabling.

### Symbol fallback list

Tried in order; the first non-nil result wins:

1. `CGSConfigureDisplayEnabled` — macOS 13 Ventura / 14 Sonoma / 15 Sequoia (primary)
2. `CGSSetDisplayEnabled` — pre-Ventura fallback
3. `SLSConfigureDisplayEnabled` — SkyLight-prefix variant, internal/debug builds
4. `SLSSetDisplayEnabled` — SkyLight-prefix variant

---

## Troubleshooting

**Symbol not found**
Run:
```sh
nm /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -iE "display|enabled"
```
This lists the actual symbol names on your macOS version. Open an issue with the output.

**Display stuck off (`elap on` not working)**
```sh
sudo killall -KILL WindowServer
```
This restarts WindowServer; macOS resets all display configuration.

**GPU didn't drop the display**
Check:
```sh
elap status
elap list --verbose
```
If status shows DISABLED but the display is visually still on, the private API may have changed.
File an issue with your macOS version and the output of the `nm` command above.

---

## macOS Compatibility

| Version | Status |
|---|---|
| 15 Sequoia | Expected to work |
| 14 Sonoma | Expected to work |
| 13 Ventura | Primary tested target |
| 12 Monterey | Below minimum (not supported) |

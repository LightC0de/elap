// ELAP — Extended Laptop Display Control
//
// Fully disconnects the MacBook's built-in display from WindowServer compositing while the
// lid stays open. Uses private SkyLight.framework APIs resolved at runtime via dlsym.
//
// The private-API resolution, display model, decision logic, and signal-recovery handlers
// live in ELAPCore (shared with the menu-bar app). This file holds the CLI-only surface:
// ArgumentParser commands, the interactive countdown/confirm flow, and the watch/daemon
// machinery that depends on process-level tricks (execv self-restart, launchctl).

import Foundation
import CoreGraphics
import ArgumentParser
import Darwin
import ELAPCore

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.6  Countdown helpers

func countdownSeconds(_ n: Int) {
    for i in stride(from: n, through: 1, by: -1) {
        print("\r  \(i)...", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1.0)
    }
    // Erase the countdown line: CR then CSI erase-entire-line (ESC [2K).
    print("\r\u{1B}[2K", terminator: "")
    fflush(stdout)
}

// Returns true if the user pressed Enter before the timeout (confirmed: keep disabled).
// Returns false if the timeout elapsed (auto-revert).
// Returns false immediately if seconds <= 0 (no thread spawned, no blocking).
func waitForEnterOrTimeout(seconds: Int) -> Bool {
    guard seconds > 0 else { return false }

    var entered = false
    let mu = NSLock()

    Thread.detachNewThread {
        _ = readLine()
        mu.lock()
        entered = true
        mu.unlock()
    }

    for elapsed in 0..<seconds {
        let remaining = seconds - elapsed
        print("\r  Auto-reverting in \(remaining)s... (Press Enter to keep disabled)", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1.0)
        mu.lock()
        let done = entered
        mu.unlock()
        if done {
            // User pressed Enter — erase the countdown line and return.
            print("\r\u{1B}[2K", terminator: "")
            fflush(stdout)
            return true
        }
    }

    // Final check after the loop.
    mu.lock()
    let finalState = entered
    mu.unlock()
    print("")  // newline after the countdown
    return finalState
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.7  Core disable logic

func disableBuiltInDisplay(force: Bool, timeout: Int, verbose: Bool) throws {
    let api      = try SkyLightAPI.load(verbose: verbose)
    let displays = fetchDisplays(verbose: verbose)

    guard let builtin = builtInDisplay(in: displays) else {
        throw DTError.noBuiltInDisplay
    }

    if !builtin.isActive {
        print("Built-in display is already disabled.")
        return
    }

    // External-display safety guard: refuse to disable if no external is active, unless
    // --force bypasses this. Leaving the user with a blank screen is the worst outcome.
    if !force {
        guard hasActiveExternalDisplay(displays) else {
            throw DTError.noExternalDisplay
        }
    }

    // 5-second countdown gives the user a chance to cancel with Ctrl+C.
    if !force {
        print("Warning: About to disable the built-in display.")
        print("  To re-enable at any time: elap on")
        print("  Press Ctrl+C to cancel")
        countdownSeconds(5)
    }

    // Persist the ID *before* disabling — once disabled, it vanishes from CGGetOnlineDisplayList.
    saveBuiltInDisplayID(builtin.id)

    try api.setEnabled(builtin.id, false)

    // Install signal handlers immediately after disable. They stay for the process's life
    // (if timeout == 0) or until removeReenableHandlers() is called after the timeout window.
    installReenableHandlers(api: api, displayID: builtin.id)

    print("Built-in display disabled. GPU is no longer rendering it.")
    print("To re-enable: elap on")

    if timeout > 0 {
        let confirmed = waitForEnterOrTimeout(seconds: timeout)
        removeReenableHandlers()

        if !confirmed {
            print("Timeout elapsed. Re-enabling built-in display...")
            try api.setEnabled(builtin.id, true)
            clearBuiltInDisplayID()
            print("Built-in display re-enabled.")
        } else {
            print("Confirmed. Built-in display stays disabled.")
        }
    }
    // If timeout == 0: handlers remain installed for the lifetime of the process.
    // This is intentional — scripts and Shortcuts bindings run with no TTY to accept Enter.
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.8  CLI commands

struct ELAPCli: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "elap",
        abstract: "Toggle the macOS built-in display on/off while keeping the lid open.",
        discussion: """
            Uses private SkyLight/CoreGraphics APIs to disconnect the built-in display from \
            WindowServer compositing, freeing the GPU from rendering it. This is not a public \
            API and may break on future macOS releases.

            Exit codes: 0 = success, 1 = error, 2 = no external display found.
            """,
        version: elapVersion,
        subcommands: [List.self, Status.self, On.self, Off.self, Toggle.self, Watch.self, Daemon.self]
    )
}

// MARK: list

extension ELAPCli {
    struct List: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List all connected displays with IDs, resolutions, and status."
        )

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            let displays = fetchDisplays(verbose: verbose)
            if displays.isEmpty {
                print("No displays found.")
                return
            }
            for (i, d) in displays.enumerated() {
                let kind  = d.isBuiltIn ? "Built-in Retina" : "External      "
                let res   = "\(Int(d.bounds.width))x\(Int(d.bounds.height))"
                let state = d.isActive ? "ENABLED" : "DISABLED"
                print("  Display \(i + 1): \(kind)  \(res.padding(toLength: 10, withPad: " ", startingAt: 0))  ID: \(d.id)  [\(state)]")
            }
        }
    }
}

// MARK: status

extension ELAPCli {
    struct Status: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Show whether the built-in display is currently enabled or disabled."
        )

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            let displays = fetchDisplays(verbose: verbose)
            guard let b = builtInDisplay(in: displays) else {
                printErr(DTError.noBuiltInDisplay)
                throw ExitCode(1)
            }
            print("Built-in display (ID: \(b.id)): \(b.isActive ? "ENABLED" : "DISABLED")")
        }
    }
}

// MARK: on

extension ELAPCli {
    struct On: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Enable the built-in display."
        )

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            do {
                let api      = try SkyLightAPI.load(verbose: verbose)
                let displays = fetchDisplays(verbose: verbose)
                guard let b = builtInDisplay(in: displays) else {
                    throw DTError.noBuiltInDisplay
                }
                if b.isActive {
                    print("Built-in display is already enabled.")
                    return
                }
                try api.setEnabled(b.id, true)
                clearBuiltInDisplayID()
                print("Built-in display re-enabled.")
            } catch let e as DTError {
                printErr(e)
                throw ExitCode(1)
            } catch {
                printErr(error)
                throw ExitCode(1)
            }
        }
    }
}

// MARK: off

extension ELAPCli {
    struct Off: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Disable the built-in display (frees GPU from rendering it)."
        )

        // Long-only --force (no -f shorthand), matching the spec.
        @Flag(help: "Skip the 5-second safety countdown and the external-display guard.")
        var force = false

        @Option(help: ArgumentHelp(
            "Auto-re-enable after N seconds if the user does not confirm. 0 = no auto-revert.",
            valueName: "seconds"
        ))
        var timeout: Int = 0

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            do {
                try disableBuiltInDisplay(force: force, timeout: timeout, verbose: verbose)
            } catch DTError.noExternalDisplay {
                printErr(DTError.noExternalDisplay)
                throw ExitCode(2)
            } catch let e as DTError {
                printErr(e)
                throw ExitCode(1)
            } catch {
                printErr(error)
                throw ExitCode(1)
            }
        }
    }
}

// MARK: toggle

extension ELAPCli {
    struct Toggle: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Toggle the built-in display: disable if enabled, enable if disabled."
        )

        // Note: although the help text mentions only the countdown, --force also bypasses
        // the external-display guard when threaded into disableBuiltInDisplay.
        @Flag(help: "Skip the 5-second safety countdown when disabling.")
        var force = false

        @Option(help: ArgumentHelp(
            "Auto-re-enable after N seconds if the user does not confirm. 0 = no auto-revert.",
            valueName: "seconds"
        ))
        var timeout: Int = 0

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            do {
                let displays = fetchDisplays(verbose: verbose)
                guard let b = builtInDisplay(in: displays) else {
                    throw DTError.noBuiltInDisplay
                }

                if b.isActive {
                    try disableBuiltInDisplay(force: force, timeout: timeout, verbose: verbose)
                } else {
                    let api = try SkyLightAPI.load(verbose: verbose)
                    try api.setEnabled(b.id, true)
                    clearBuiltInDisplayID()
                    print("Built-in display enabled.")
                }
            } catch DTError.noExternalDisplay {
                printErr(DTError.noExternalDisplay)
                throw ExitCode(2)
            } catch let e as DTError {
                printErr(e)
                throw ExitCode(1)
            } catch {
                printErr(error)
                throw ExitCode(1)
            }
        }
    }
}

// MARK: watch

// Module-level globals for the CGDisplayRegisterReconfigurationCallback C callback — C callbacks
// cannot capture Swift closures, so we store shared state at module scope.
private var _watchAPI: SkyLightAPI? = nil
private var _watchVerbose: Bool = false
// Tracks whether watch is in auto-manage mode: true after the first auto-enable (or if the
// built-in was already disabled when watch started). In this mode, watch also auto-disables
// the built-in when a real external display reconnects, completing the bidirectional cycle.
private var _watchAutoModeActive: Bool = false

private func watchTimestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

// Edge-triggered snapshot tracking: remembers the last raw CG snapshot so the watch loop can log
// a line *only when the topology CoreGraphics reports actually changes*. Low-noise, and always on
// (not gated behind --verbose) so the daemon log captures the moment of failure.
private var _watchLastRawSnapshot: String? = nil

// Resolves the absolute path of the currently-running executable. Used to re-exec a fresh copy
// of ourselves. _NSGetExecutablePath is reliable even when launched via PATH (where argv[0] is
// just "elap"); we canonicalize it with realpath to follow any symlinks.
private func currentExecutablePath() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size) + 1)
    if _NSGetExecutablePath(&buf, &size) == 0 {
        if let resolved = realpath(buf, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return String(cString: buf)
    }
    return ProcessInfo.processInfo.arguments.first ?? "elap"
}

// Workaround for a CoreGraphics limitation observed on macOS: once this process performs a
// display reconfiguration (CGCompleteDisplayConfiguration), its per-process display state
// freezes — CGGetOnlineDisplayList stops updating and reconfiguration callbacks stop firing, so
// every subsequent hot-plug/unplug becomes invisible to this process. Re-executing ourselves
// yields a fresh WindowServer connection that sees current reality.
//
// Called only immediately after an actual toggle (i.e. on real display changes), so it never
// busy-loops: a freshly-restarted process evaluates the just-settled state and finds nothing to
// do, so it will not toggle (and thus not restart) again until the next real hot-plug event.
//
// On success execv never returns. On the (very unlikely) failure path we log and return so the
// caller keeps watching in degraded mode rather than dying — preserving the recovery path.
private func restartWatchForFreshCGState() {
    print("[watch] \(watchTimestamp()) restarting watch to refresh CoreGraphics display state…")
    fflush(stdout)
    fflush(stderr)

    let exePath = currentExecutablePath()
    var argv = ProcessInfo.processInfo.arguments
    if argv.isEmpty { argv = [exePath] } else { argv[0] = exePath }

    // Preserve auto-manage mode across the restart so reconnect → auto-disable keeps working
    // even when the restart happens with the built-in already on (see Watch.run startup).
    setenv("ELAP_WATCH_AUTOMODE", _watchAutoModeActive ? "1" : "0", 1)

    var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
    cargs.append(nil)

    execv(exePath, &cargs)

    // Only reached if execv failed.
    perror("[watch] execv failed; continuing without restart")
    fflush(stderr)
    for p in cargs where p != nil { free(p) }
}

// Checks display state and acts if needed (enable or disable built-in).
// Must be called on the main thread only. Safe to call repeatedly — all paths are guarded.
func watchCheckAndReenableIfNeeded() {
    // Capture CoreGraphics' raw view first. Edge-triggered: log (always, not just --verbose)
    // whenever the raw topology changes. If a physical disconnect does NOT produce a line here,
    // CoreGraphics handed us a stale display list — the prime suspect for missed disconnects.
    let rawSnapshot = rawOnlineDisplaySnapshot()
    if rawSnapshot != _watchLastRawSnapshot {
        print("[watch] \(watchTimestamp()) CG topology changed: \(rawSnapshot)")
        fflush(stdout)
        _watchLastRawSnapshot = rawSnapshot
    }

    let displays = fetchDisplays(verbose: _watchVerbose)
    let hasExt   = hasActiveExternalDisplay(displays)

    if _watchVerbose {
        let builtInState = builtInDisplay(in: displays)?.isActive == true ? "on" : "off"
        print("[watch] \(watchTimestamp()) tick — auto=\(_watchAutoModeActive), built-in=\(builtInState), real-ext=\(hasExt), raw=\(rawSnapshot)")
        fflush(stdout)
    }

    // Auto-disable path: external reconnected while built-in is on (auto-manage mode only).
    if _watchAutoModeActive && shouldAutoDisableBuiltIn(displays: displays) {
        guard let builtin = builtInDisplay(in: displays) else { return }
        if _watchVerbose { print("[watch] → auto-disable: real external appeared, built-in is on") }
        print("External display connected — disabling built-in display… (built-in ID: \(builtin.id))")
        saveBuiltInDisplayID(builtin.id)
        do {
            try _watchAPI?.setEnabled(builtin.id, false)
            print("Built-in display disabled.")
            // CoreGraphics freezes our display view after this reconfiguration; restart for a
            // fresh connection so the next disconnect is still detected. (Does not return on success.)
            restartWatchForFreshCGState()
        } catch {
            printErr(error)
        }
        return
    }

    // Auto-enable path: all externals gone while built-in is off.
    guard shouldReenableBuiltIn(displays: displays) else {
        if _watchVerbose {
            let builtInActive = builtInDisplay(in: displays)?.isActive == true
            let reason: String
            if builtInActive && hasExt {
                reason = "both on — steady state"
            } else if !builtInActive && hasExt {
                reason = "built-in off, external on — waiting for disconnect"
            } else if builtInActive && !hasExt {
                reason = "built-in on, no external — nothing to re-enable"
            } else if !_watchAutoModeActive && shouldAutoDisableBuiltIn(displays: displays) {
                reason = "auto-mode not yet active — connect external then disconnect to activate"
            } else {
                reason = "no built-in found in display list"
            }
            print("[watch] No action: \(reason).")
        }
        return
    }
    guard let builtin = builtInDisplay(in: displays) else { return }
    if _watchVerbose { print("[watch] → re-enable: no real external, built-in is off") }
    print("All external displays disconnected — enabling built-in display… (built-in ID: \(builtin.id))")
    do {
        try _watchAPI?.setEnabled(builtin.id, true)
        clearBuiltInDisplayID()
        if !_watchAutoModeActive {
            _watchAutoModeActive = true
            if _watchVerbose { print("[watch] Auto-manage mode activated.") }
        }
        print("Built-in display enabled.")
        // CoreGraphics freezes our display view after this reconfiguration; restart for a fresh
        // connection so a later reconnect/disconnect is still detected. (Does not return on success.)
        restartWatchForFreshCGState()
    } catch {
        printErr(error)
    }
}

extension ELAPCli {
    struct Watch: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Watch for display changes; auto-enable built-in when all external displays disconnect."
        )

        @Flag(name: .shortAndLong, help: "Show verbose debug output.")
        var verbose = false

        func run() throws {
            do {
                _watchAPI     = try SkyLightAPI.load(verbose: verbose)
                _watchVerbose = verbose
            } catch let e as DTError {
                printErr(e)
                throw ExitCode(1)
            } catch {
                printErr(error)
                throw ExitCode(1)
            }

            // If we were re-exec'd after a toggle (restartWatchForFreshCGState), restore the
            // auto-manage state we carried across in the environment so the cycle continues
            // seamlessly even when the built-in is currently on.
            if ProcessInfo.processInfo.environment["ELAP_WATCH_AUTOMODE"] == "1" {
                _watchAutoModeActive = true
                if verbose { print("[verbose] Auto-manage mode restored after restart.") }
            }

            // If the built-in is already disabled (user ran `elap off` before starting watch),
            // enter auto-manage mode immediately so the full cycle works from the first tick.
            let initialDisplays = fetchDisplays(verbose: false)
            if let b = builtInDisplay(in: initialDisplays), !b.isActive {
                _watchAutoModeActive = true
                if verbose { print("[verbose] Built-in already disabled — auto-manage mode active from start.") }
            }

            print("Watching display changes. Built-in will be managed automatically:")
            print("  External disconnects → built-in turns on")
            print("  External reconnects  → built-in turns off  (once auto-manage is active)")
            print("Press Ctrl+C to stop.")

            // Fast path: CGDisplayRegisterReconfigurationCallback fires for display changes.
            // Dispatched async so CGBeginDisplayConfiguration (inside setEnabled) is never
            // called re-entrantly from within the reconfiguration callback itself.
            // NOTE: in some CLI contexts this callback may not be delivered reliably;
            // the timer below is the primary reliable mechanism.
            CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
                guard !flags.contains(.beginConfigurationFlag) else { return }
                if _watchVerbose {
                    var parts: [String] = []
                    if flags.contains(.addFlag)                 { parts.append("add") }
                    if flags.contains(.removeFlag)              { parts.append("remove") }
                    if flags.contains(.enabledFlag)             { parts.append("enabled") }
                    if flags.contains(.disabledFlag)            { parts.append("disabled") }
                    if flags.contains(.movedFlag)               { parts.append("moved") }
                    if flags.contains(.setMainFlag)             { parts.append("setMain") }
                    if flags.contains(.desktopShapeChangedFlag) { parts.append("shapeChanged") }
                    let decoded = parts.isEmpty ? "0x\(String(flags.rawValue, radix: 16))" : parts.joined(separator: "|")
                    print("[watch] \(watchTimestamp()) callback: \(decoded) — scheduling check…")
                }
                DispatchQueue.main.async { watchCheckAndReenableIfNeeded() }
            }, nil)

            // Primary mechanism: poll every 2 seconds. CGDisplayRegisterReconfigurationCallback
            // delivery is unreliable in CLI (non-app-bundle) processes because the callback is
            // tied to the WindowServer notification port and may not be delivered when the
            // process has no active GUI session. Polling via RunLoop timer is always reliable.
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                watchCheckAndReenableIfNeeded()
            }

            // RunLoop.main.run() is required (not dispatchMain) because
            // CGDisplayRegisterReconfigurationCallback is a CFRunLoop-based mechanism — it
            // delivers callbacks through the main run loop, not the GCD main queue.
            RunLoop.main.run()
        }
    }
}

// MARK: daemon

extension ELAPCli {
    struct Daemon: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Manage the background watch daemon (auto-enables built-in on external disconnect).",
            subcommands: [Install.self, Uninstall.self, DaemonStatus.self]
        )

        static let agentLabel = "com.elap.watch"

        static var plistPath: String {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist").path
        }

        // MARK: daemon install

        struct Install: ParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Install and start the watch daemon as a login agent."
            )

            func run() throws {
                // Resolve the running binary's real path (following symlinks).
                // The realpath() result is malloc'd — must free it.
                var binaryPath: String
                let rawPath = ProcessInfo.processInfo.arguments[0]
                if let resolved = realpath(rawPath, nil) {
                    binaryPath = String(cString: resolved)
                    free(resolved)
                } else {
                    binaryPath = (rawPath as NSString).standardizingPath
                }

                let label    = Daemon.agentLabel
                let plist    = Daemon.plistPath

                let plistContent = """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>Label</key>
                        <string>\(label)</string>
                        <key>ProgramArguments</key>
                        <array>
                            <string>\(binaryPath)</string>
                            <string>watch</string>
                        </array>
                        <key>RunAtLoad</key>
                        <true/>
                        <key>KeepAlive</key>
                        <true/>
                        <key>StandardOutPath</key>
                        <string>/tmp/elap-daemon.log</string>
                        <key>StandardErrorPath</key>
                        <string>/tmp/elap-daemon.log</string>
                    </dict>
                    </plist>
                    """

                do {
                    try plistContent.write(toFile: plist, atomically: true, encoding: .utf8)
                } catch {
                    fputs("Error writing plist: \(error.localizedDescription)\n", stderr)
                    throw ExitCode(1)
                }

                let uid = getuid()

                // Clear any stale instance; errors ignored.
                _ = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

                let (out, err, code) = runLaunchctl(["bootstrap", "gui/\(uid)", plist])
                if code != 0 {
                    fputs("launchctl bootstrap failed (exit \(code)):\n\(err)\(out)", stderr)
                    throw ExitCode(1)
                }

                print("Daemon installed and started.")
                print("  Binary: \(binaryPath)")
                print("  Plist:  \(plist)")
                print("  Logs:   /tmp/elap-daemon.log")
                print("The daemon will restart automatically at login.")
            }
        }

        // MARK: daemon uninstall

        struct Uninstall: ParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Stop and remove the watch daemon."
            )

            func run() throws {
                let label = Daemon.agentLabel
                let uid   = getuid()
                let (out, err, code) = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

                if code != 0 {
                    let combined = out + err
                    let alreadyStopped = combined.contains("No such process")
                        || combined.contains("Could not find")
                        || combined.contains("not loaded")
                    if !alreadyStopped {
                        fputs("launchctl bootout failed (exit \(code)):\n\(err)\(out)", stderr)
                        throw ExitCode(1)
                    }
                } else {
                    print("Daemon stopped.")
                }

                let plist = Daemon.plistPath
                if FileManager.default.fileExists(atPath: plist) {
                    try? FileManager.default.removeItem(atPath: plist)
                }

                print("Daemon uninstalled.")
            }
        }

        // MARK: daemon status
        // Named DaemonStatus to avoid collision with the top-level Status command type.

        struct DaemonStatus: ParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "status",
                abstract: "Show whether the watch daemon is currently running."
            )

            func run() throws {
                let label   = Daemon.agentLabel
                let uid     = getuid()
                let (out, _, code) = runLaunchctl(["print", "gui/\(uid)/\(label)"])

                if code == 0 {
                    if let pidLine = out.split(separator: "\n")
                        .map({ $0.trimmingCharacters(in: .whitespaces) })
                        .first(where: { $0.hasPrefix("pid") }) {
                        print("Daemon is RUNNING (\(pidLine)).")
                    } else {
                        print("Daemon is RUNNING.")
                    }
                } else {
                    print("Daemon is NOT running.")
                    print("  To install: elap daemon install")
                }
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.9  Helpers

@discardableResult
private func runLaunchctl(_ args: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    proc.arguments = args

    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError  = errPipe

    do {
        try proc.run()
    } catch {
        return ("", error.localizedDescription, 1)
    }

    proc.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: outData, encoding: .utf8) ?? ""
    let err = String(data: errData, encoding: .utf8) ?? ""
    return (out, err, proc.terminationStatus)
}

func printErr(_ error: Error) {
    let msg: String
    if let dt = error as? DTError {
        msg = dt.errorDescription ?? dt.localizedDescription
    } else {
        msg = error.localizedDescription
    }
    fputs("Error: \(msg)\n", stderr)
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.10  Entry point

ELAPCli.main()

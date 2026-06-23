// ELAP — Extended Laptop Display Control
//
// Fully disconnects the MacBook's built-in display from WindowServer compositing while the
// lid stays open. Uses private SkyLight.framework APIs resolved at runtime via dlsym.
//
// PRIVATE-API CAVEAT: The symbols used here (CGSConfigureDisplayEnabled and friends) are
// undocumented private SPI. They work from user space without disabling SIP. However, they
// WILL break on any future macOS release that renames or removes these symbols — there is no
// @available guard for private functions. If the tool stops working, run:
//   nm /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -iE "display|enabled"
// and open an issue with the output.

import Foundation
import CoreGraphics
import ArgumentParser
import Darwin

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.1  Private-API typealias

// The function signature of CGSConfigureDisplayEnabled.
//
// CRITICAL: The first argument is a CGDisplayConfigRef obtained from CGBeginDisplayConfiguration()
// — NOT a CGSConnectionID integer. This is a private complement to the standard CoreGraphics
// display-configuration transaction. Passing an integer would be dereferenced as a pointer
// and crash immediately. Always call CGBeginDisplayConfiguration first and pass its output.
//
// Returns 0 on success, non-zero on failure.
typealias CGSSetDisplayEnabledFn = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> Int32

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.2  Symbol loader — struct SkyLightAPI

struct SkyLightAPI {
    let _setEnabled: CGSSetDisplayEnabledFn
    let symbolName: String

    // Wraps the private toggle inside the standard public CoreGraphics display-configuration
    // transaction. Using .permanently means the change survives process exit but reverts on
    // logout or reboot — the intended recovery backstop.
    func setEnabled(_ displayID: CGDirectDisplayID, _ enabled: Bool) throws {
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config = config else {
            throw DTError.apiFailure("CGBeginDisplayConfiguration", err.rawValue)
        }

        let ret = _setEnabled(config, displayID, enabled)
        if ret != 0 {
            CGCancelDisplayConfiguration(config)
            throw DTError.apiFailure(symbolName, ret)
        }

        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else {
            throw DTError.apiFailure("CGCompleteDisplayConfiguration", err.rawValue)
        }
    }

    static func load(verbose: Bool = false) throws -> SkyLightAPI {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

        // Build a prioritized list of dlopen handles. We try:
        //   1. RTLD_NOLOAD — if SkyLight is already mapped into the process (likely), reuse it.
        //   2. A fresh dlopen — load it if not already mapped.
        //   3. nil (global symbol table) — last resort; catches symbols exported globally.
        var handles: [UnsafeMutableRawPointer?] = []
        if let h = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) { handles.append(h) }
        if let h = dlopen(path, RTLD_LAZY) { handles.append(h) }
        handles.append(dlopen(nil, RTLD_LAZY))

        // Lazy short-circuit: returns the first non-nil dlsym result across all handles.
        func find(_ name: String) -> UnsafeMutableRawPointer? {
            handles.lazy.compactMap { dlsym($0, name) }.first
        }

        // Candidate symbols, tried in priority order. The name changed across macOS versions;
        // some internal/debug builds use the SLS- prefix instead of CGS-.
        let candidates = [
            "CGSConfigureDisplayEnabled",   // macOS 13 Ventura / 14 Sonoma / 15 Sequoia — primary
            "CGSSetDisplayEnabled",          // pre-Ventura fallback
            "SLSConfigureDisplayEnabled",    // SkyLight-prefix variant, internal/debug builds
            "SLSSetDisplayEnabled",          // SkyLight-prefix variant
        ]

        for name in candidates {
            guard let sym = find(name) else { continue }
            if verbose { print("[verbose] Using symbol: \(name)") }
            let fn = unsafeBitCast(sym, to: CGSSetDisplayEnabledFn.self)
            return SkyLightAPI(_setEnabled: fn, symbolName: name)
        }

        throw DTError.symbolNotFound(candidates)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.3  Errors

enum DTError: Error, LocalizedError {
    case noBuiltInDisplay
    case noExternalDisplay
    case symbolNotFound([String])
    case apiFailure(String, Int32)

    var errorDescription: String? {
        switch self {
        case .noBuiltInDisplay:
            return "No built-in display detected on this machine."

        case .noExternalDisplay:
            return """
                No active external display found.
                Refusing to disable the built-in display — that would leave you with a blank screen.
                Connect an external monitor and retry.
                (Use --force to bypass this check.)
                """

        case .symbolNotFound(let names):
            let list = names.map { "  \($0)" }.joined(separator: "\n")
            let ver = ProcessInfo.processInfo.operatingSystemVersionString
            return """
                Could not resolve the private display-toggle symbol. Tried:
                \(list)
                macOS \(ver)
                Run: nm /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -iE "display|enabled"
                """

        case .apiFailure(let sym, let code):
            return "Private API '\(sym)' returned error code \(code)."
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.4  Display model, state file & discovery

struct DisplayInfo {
    let id: CGDirectDisplayID
    let isBuiltIn: Bool
    let isActive: Bool
    let bounds: CGRect
}

// State-file path. A disabled display vanishes from CGGetOnlineDisplayList, so we persist
// its ID before disabling and recover it afterward. The path is fixed and well-known so
// recovery tools (including a bare `elap on` run from another terminal) can always find it.
//
// Computed property instead of a stored `let` to avoid Swift lazy-global-initialization
// issues when the ELAP module is @testable-imported by the test binary (the lazy dispatch_once
// for a `private let` in main.swift can run before the Swift runtime is fully set up in the
// test harness, leaving the string zero-backed and crashing on first access).
private var stateFilePath: String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".elap-builtin-id").path
}

func saveBuiltInDisplayID(_ id: CGDirectDisplayID) {
    try? String(id).write(toFile: stateFilePath, atomically: true, encoding: .utf8)
}

func clearBuiltInDisplayID() {
    try? FileManager.default.removeItem(atPath: stateFilePath)
}

func loadSavedBuiltInDisplayID() -> CGDirectDisplayID? {
    guard let raw = try? String(contentsOfFile: stateFilePath, encoding: .utf8) else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return CGDirectDisplayID(trimmed)
}

func fetchDisplays(verbose: Bool = false) -> [DisplayInfo] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)

    var infos: [DisplayInfo] = ids.map { id in
        let builtIn = CGDisplayIsBuiltin(id) != 0
        let active  = CGDisplayIsActive(id) != 0
        let bounds  = CGDisplayBounds(id)
        if verbose {
            let kind  = builtIn ? "built-in" : "external"
            let state = active  ? "active"   : "INACTIVE"
            let w     = Int(bounds.width)
            let h     = Int(bounds.height)
            print("[verbose] Display \(id): \(kind), \(state), \(w)x\(h)")
        }
        return DisplayInfo(id: id, isBuiltIn: builtIn, isActive: active, bounds: bounds)
    }

    // Recovery: if no built-in appears in the online list, it was previously disabled and
    // dropped out. Recover its ID so `elap on` and friends can still target it.
    if !infos.contains(where: { $0.isBuiltIn }) {
        var recoveredID: CGDirectDisplayID? = nil

        // Strategy 1 (primary): hardware probe. CGDisplayIsBuiltin queries hardware even for
        // offline displays, so walking 1...32 finds the built-in without needing the state file.
        for probe: CGDirectDisplayID in 1...32 {
            if CGDisplayIsBuiltin(probe) != 0 {
                recoveredID = probe
                if verbose { print("[verbose] Built-in display recovered via ID probe: \(probe)") }
                break
            }
        }

        // Strategy 2 (fallback): state file written just before disable.
        if recoveredID == nil, let saved = loadSavedBuiltInDisplayID() {
            recoveredID = saved
            if verbose { print("[verbose] Built-in display recovered via state file: \(saved)") }
        }

        if let id = recoveredID {
            // isActive: false, bounds: .zero — it is invisible/offline.
            infos.append(DisplayInfo(id: id, isBuiltIn: true, isActive: false, bounds: .zero))
        }
    }

    return infos
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.4 helpers (internal, for testability)

// Returns true if any external display is currently active (composited by WindowServer).
// Extracted as an internal function so tests can exercise it without spawning the full CLI.
func hasActiveExternalDisplay(_ displays: [DisplayInfo]) -> Bool {
    displays.contains { !$0.isBuiltIn && $0.isActive }
}

// Returns the first built-in display in the list, or nil if none is present.
func builtInDisplay(in displays: [DisplayInfo]) -> DisplayInfo? {
    displays.first { $0.isBuiltIn }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: §2.5  Signal handlers (re-enable on Ctrl+C / SIGTERM)

// C signal callbacks cannot capture Swift closures, so we store the API and display ID in
// module-level globals. The handler reinstates the default disposition and re-raises the
// signal so the shell sees the correct exit status.
private var _sigDisplayID: CGDirectDisplayID = 0
private var _sigSetFn: CGSSetDisplayEnabledFn? = nil

func installReenableHandlers(api: SkyLightAPI, displayID: CGDirectDisplayID) {
    _sigDisplayID = displayID
    _sigSetFn = api._setEnabled

    let handler: @convention(c) (Int32) -> Void = { sig in
        if let fn = _sigSetFn {
            var cfg: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&cfg) == .success, let cfg = cfg {
                _ = fn(cfg, _sigDisplayID, true)
                _ = CGCompleteDisplayConfiguration(cfg, .permanently)
            }
        }
        signal(sig, SIG_DFL)
        kill(getpid(), sig)
    }

    signal(SIGINT,  handler)
    signal(SIGTERM, handler)
}

func removeReenableHandlers() {
    signal(SIGINT,  SIG_DFL)
    signal(SIGTERM, SIG_DFL)
}

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
            }

            print("Watching display changes. Built-in will be enabled automatically")
            print("when all external displays disconnect. Press Ctrl+C to stop.")

            CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
                // The callback fires twice per change (begin + end). Act only on the post-change
                // notification, and only when a display was removed.
                guard !flags.contains(.beginConfigurationFlag) else { return }
                guard flags.contains(.removeFlag) else { return }

                if _watchVerbose { print("[watch] External display removed, checking state…") }

                let displays = fetchDisplays(verbose: _watchVerbose)

                // If any external is still active, nothing to do.
                guard !displays.contains(where: { !$0.isBuiltIn && $0.isActive }) else { return }

                guard let builtin = builtInDisplay(in: displays) else { return }

                if builtin.isActive {
                    if _watchVerbose { print("[watch] No external displays; built-in already enabled.") }
                    return
                }

                print("All external displays disconnected — enabling built-in display…")
                do {
                    try _watchAPI?.setEnabled(builtin.id, true)
                    clearBuiltInDisplayID()
                    print("Built-in display enabled.")
                } catch {
                    printErr(error)
                }
            }, nil)

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

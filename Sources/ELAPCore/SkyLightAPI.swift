// ELAPCore — private SkyLight SPI resolution and the display-toggle transaction.
//
// PRIVATE-API CAVEAT: The symbols used here (CGSConfigureDisplayEnabled and friends) are
// undocumented private SPI. They work from user space without disabling SIP. However, they
// WILL break on any future macOS release that renames or removes these symbols — there is no
// @available guard for private functions. If the tool stops working, run:
//   nm /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -iE "display|enabled"
// and open an issue with the output.

import Foundation
import CoreGraphics
import Darwin

// The function signature of CGSConfigureDisplayEnabled.
//
// CRITICAL: The first argument is a CGDisplayConfigRef obtained from CGBeginDisplayConfiguration()
// — NOT a CGSConnectionID integer. This is a private complement to the standard CoreGraphics
// display-configuration transaction. Passing an integer would be dereferenced as a pointer
// and crash immediately. Always call CGBeginDisplayConfiguration first and pass its output.
//
// Returns 0 on success, non-zero on failure.
public typealias CGSSetDisplayEnabledFn = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> Int32

public struct SkyLightAPI {
    let _setEnabled: CGSSetDisplayEnabledFn
    let symbolName: String

    // Wraps the private toggle inside the standard public CoreGraphics display-configuration
    // transaction. Using .permanently means the change survives process exit but reverts on
    // logout or reboot — the intended recovery backstop.
    public func setEnabled(_ displayID: CGDirectDisplayID, _ enabled: Bool) throws {
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

    public static func load(verbose: Bool = false) throws -> SkyLightAPI {
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

public enum DTError: Error, LocalizedError {
    case noBuiltInDisplay
    case noExternalDisplay
    case symbolNotFound([String])
    case apiFailure(String, Int32)

    public var errorDescription: String? {
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

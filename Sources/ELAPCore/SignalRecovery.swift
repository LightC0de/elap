// ELAPCore — re-enable the built-in display on Ctrl+C / SIGTERM.

import Foundation
import CoreGraphics
import Darwin

// C signal callbacks cannot capture Swift closures, so we store the API and display ID in
// module-level globals. The handler reinstates the default disposition and re-raises the
// signal so the shell sees the correct exit status.
private var _sigDisplayID: CGDirectDisplayID = 0
private var _sigSetFn: CGSSetDisplayEnabledFn? = nil

public func installReenableHandlers(api: SkyLightAPI, displayID: CGDirectDisplayID) {
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

public func removeReenableHandlers() {
    signal(SIGINT,  SIG_DFL)
    signal(SIGTERM, SIG_DFL)
}

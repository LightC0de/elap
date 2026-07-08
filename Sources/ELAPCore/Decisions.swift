// ELAPCore — pure decision logic over display snapshots. Safe to unit test.

// Returns true if any real external display is currently active (composited by WindowServer).
// Filters out virtual/headless displays (physicalSize == .zero) — macOS and some USB-C docks
// create dummy framebuffers that appear active but have no physical panel behind them.
public func hasActiveExternalDisplay(_ displays: [DisplayInfo]) -> Bool {
    displays.contains {
        !$0.isBuiltIn &&
        $0.isActive &&
        ($0.physicalSize.width > 0 || $0.physicalSize.height > 0)
    }
}

// Returns the first built-in display in the list, or nil if none is present.
public func builtInDisplay(in displays: [DisplayInfo]) -> DisplayInfo? {
    displays.first { $0.isBuiltIn }
}

// Returns true when the built-in should be re-enabled: no external display is active
// AND the built-in is currently disabled. Pure function — safe to call from tests.
public func shouldReenableBuiltIn(displays: [DisplayInfo]) -> Bool {
    guard !hasActiveExternalDisplay(displays) else { return false }
    guard let builtin = builtInDisplay(in: displays) else { return false }
    return !builtin.isActive
}

// Returns true when the built-in should be disabled automatically: a real external is active
// and the built-in is on. Used by watch's auto-manage mode. Pure function — safe to call from tests.
public func shouldAutoDisableBuiltIn(displays: [DisplayInfo]) -> Bool {
    guard hasActiveExternalDisplay(displays) else { return false }
    guard let builtin = builtInDisplay(in: displays) else { return false }
    return builtin.isActive
}

// Returns true when the current display state would leave the user with no working screen:
// the built-in is off and no real external is active. Used by the app's quit hook to decide
// whether it must re-enable the built-in before terminating. Pure function — safe to test.
public func wouldStrandUser(displays: [DisplayInfo]) -> Bool {
    guard let builtin = builtInDisplay(in: displays) else { return false }
    return !builtin.isActive && !hasActiveExternalDisplay(displays)
}

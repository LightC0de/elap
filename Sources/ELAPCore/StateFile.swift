// ELAPCore — state-file persistence for the built-in display ID.

import Foundation
import CoreGraphics

// State-file path. A disabled display vanishes from CGGetOnlineDisplayList, so we persist
// its ID before disabling and recover it afterward. The path is fixed and well-known so
// recovery tools (including a bare `elap on` run from another terminal) can always find it.
//
// Computed property instead of a stored `let` to avoid Swift lazy-global-initialization
// issues when this module is @testable-imported by the test binary (the lazy dispatch_once
// for a top-level `let` can run before the Swift runtime is fully set up in the test harness,
// leaving the string zero-backed and crashing on first access).
var stateFilePath: String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".elap-builtin-id").path
}

public func saveBuiltInDisplayID(_ id: CGDirectDisplayID) {
    try? String(id).write(toFile: stateFilePath, atomically: true, encoding: .utf8)
}

public func clearBuiltInDisplayID() {
    try? FileManager.default.removeItem(atPath: stateFilePath)
}

public func loadSavedBuiltInDisplayID() -> CGDirectDisplayID? {
    guard let raw = try? String(contentsOfFile: stateFilePath, encoding: .utf8) else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return CGDirectDisplayID(trimmed)
}

// ELAPApp — read-only detector for the CLI's `elap daemon` (background `watch` loop).
//
// If the daemon is installed while the app's auto-manage switch is on, both will race to
// toggle the built-in display independently. This only warns; it never touches launchd
// state itself (installing/uninstalling the daemon is exclusively `elap daemon install/uninstall`).

import Foundation

enum WatchDaemonDetector {
    // Matches Daemon.agentLabel / Daemon.plistPath in Sources/ELAP/main.swift.
    private static let agentLabel = "com.elap.watch"

    private static var plistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist").path
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func isRunning() -> Bool {
        let uid = getuid()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["print", "gui/\(uid)/\(agentLabel)"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return false
        }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    // Conservative: a plist file alone can be stale (bootout without removing it), so the
    // conflict warning only fires when launchctl confirms the daemon is actually running.
    static func isConflicting() -> Bool {
        isInstalled() && isRunning()
    }
}

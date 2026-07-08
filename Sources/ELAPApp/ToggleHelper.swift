// ELAPApp — locates and runs the bundled `elap` CLI as a short-lived subprocess.
//
// The app never mutates displays in-process: CGCompleteDisplayConfiguration freezes a
// process's own CG display list, so all state-changing calls are delegated to the `elap`
// binary via Process. See menu-bar-app-plan.md item 2.

import Foundation

enum ToggleHelperError: Error, LocalizedError {
    case helperNotFound
    case processFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "Could not find the elap helper binary."
        case .processFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "elap exited with code \(exitCode)." : trimmed
        }
    }
}

enum ToggleHelper {
    // Resolution order: bundled app resource → sibling of the running executable →
    // debug/release build products (dev loop) → /usr/local/bin (system install).
    static func locate() -> String? {
        let fm = FileManager.default

        if let bundled = Bundle.main.url(forResource: "elap", withExtension: nil)?.path,
           fm.isExecutableFile(atPath: bundled) {
            return bundled
        }

        let executableURL = Bundle.main.executableURL
        if let sibling = executableURL?.deletingLastPathComponent().appendingPathComponent("elap").path,
           fm.isExecutableFile(atPath: sibling) {
            return sibling
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ToggleHelper.swift
            .deletingLastPathComponent() // ELAPApp
            .deletingLastPathComponent() // Sources
        for config in ["release", "debug"] {
            let candidate = root.appendingPathComponent(".build/\(config)/elap").path
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        let systemPath = "/usr/local/bin/elap"
        if fm.isExecutableFile(atPath: systemPath) {
            return systemPath
        }

        return nil
    }

    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        guard let path = locate() else {
            throw ToggleHelperError.helperNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: ToggleHelperError.processFailed(exitCode: proc.terminationStatus, stderr: stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func turnOff() async throws {
        try await run(["off", "--force"])
    }

    static func turnOn() async throws {
        try await run(["on"])
    }
}

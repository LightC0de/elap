// ELAPApp — auto-manage: the app-side equivalent of the CLI's `elap watch`.
//
// Unlike `watch`'s activation latch (which only starts auto-disabling after its first
// auto-enable, so a fresh `watch` run never disables a display the user left on deliberately),
// the app switch is explicit user intent: while it's on, both directions are unconditional.
// Driven by DisplayStateModel's own refresh cadence (reconfiguration callback + poll timer),
// so this engine just reacts to state the model already keeps fresh — see DisplayStateModel.swift.

import Foundation
import ELAPCore

@MainActor
final class AutoManageEngine: ObservableObject {
    static let enabledDefaultsKey = "autoManageEnabled"

    // True when the CLI's `elap daemon` is installed and actively running alongside auto-manage
    // — the two would otherwise race to toggle the built-in display independently.
    @Published private(set) var daemonConflictDetected = false

    private weak var displayState: DisplayStateModel?
    private var isRunning = false

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    init(displayState: DisplayStateModel) {
        self.displayState = displayState
    }

    // Called whenever DisplayStateModel refreshes. Never overlaps a helper invocation with
    // another — re-checks after the in-flight one completes so a rapid sequence of hot-plug
    // events converges instead of racing.
    func evaluate(displays: [DisplayInfo]) {
        guard isEnabled else {
            daemonConflictDetected = false
            return
        }
        daemonConflictDetected = WatchDaemonDetector.isConflicting()

        guard !isRunning else { return }

        if shouldAutoDisableBuiltIn(displays: displays) {
            run { try await ToggleHelper.turnOff() }
        } else if shouldReenableBuiltIn(displays: displays) {
            run { try await ToggleHelper.turnOn() }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isRunning = true
        Task {
            defer { isRunning = false }
            do {
                try await action()
            } catch {
                // Best-effort: surface via the shared model so the panel can show it, then let
                // the next refresh re-evaluate — a failed toggle isn't fatal to auto-manage.
                displayState?.lastErrorMessage = error.localizedDescription
            }
            displayState?.refresh()
        }
    }
}

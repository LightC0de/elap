// ELAPApp — observable display state, kept fresh via reconfiguration callback + polling.
//
// The app never mutates displays in-process (see ToggleHelper.swift), so its own CG display
// list never goes stale — CGDisplayRegisterReconfigurationCallback stays reliable for the
// lifetime of the process. Polling is a cheap backstop for edge cases the callback might miss.

import Foundation
import CoreGraphics
import ELAPCore

@MainActor
final class DisplayStateModel: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var builtInIsOn: Bool = true
    @Published private(set) var hasRealExternal: Bool = false
    @Published var isBusy: Bool = false
    @Published var lastErrorMessage: String?
    // Bumped on every refresh() so the menu bar label can force a fresh view (via `.id()`)
    // instead of diff-updating in place — works around SwiftUI/AppKit leaving the status item's
    // icon blank (though still clickable) after the menu bar migrates to another screen when the
    // built-in display turns off.
    @Published private(set) var refreshToken: Int = 0

    // Set once by ELAPMenuBarApp after construction. Weak because the engine is owned
    // alongside this model, not by it — avoids a retain cycle between the two.
    weak var autoManageEngine: AutoManageEngine?

    private var pollTimer: Timer?
    private var reconfigToken: Bool = false

    init() {
        refresh()
        registerReconfigurationCallback()
    }

    func refresh() {
        displays = fetchDisplays()
        hasRealExternal = hasActiveExternalDisplay(displays)
        builtInIsOn = builtInDisplay(in: displays)?.isActive ?? true
        autoManageEngine?.evaluate(displays: displays)
        refreshToken += 1
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func registerReconfigurationCallback() {
        guard !reconfigToken else { return }
        reconfigToken = true
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo else { return }
            let model = Unmanaged<DisplayStateModel>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                model.refresh()
            }
        }, observer)
    }

    // Toggles the built-in display via the bundled `elap` CLI subprocess. Guarded: turning off
    // requires a real external display to be active, mirroring the CLI's own guard (and
    // replacing its interactive countdown, which doesn't apply to a UI-driven toggle).
    func toggleBuiltIn() async {
        guard !isBusy else { return }
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        do {
            if builtInIsOn {
                guard hasRealExternal else {
                    lastErrorMessage = "Connect an external display before turning the built-in display off."
                    return
                }
                try await ToggleHelper.turnOff()
            } else {
                try await ToggleHelper.turnOn()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }
}

// ELAPApp — launch-at-login via SMAppService.
//
// SMAppService.mainApp is the source of truth for login-item state — not duplicated in
// UserDefaults, so it stays correct even if the user changes it from System Settings directly.
// SMAppService only functions for a proper .app bundle (stable bundle ID, Info.plist); running
// unbundled via `swift run ELAPApp` for UI iteration, toggling is disabled with a hint.

import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    enum State {
        case enabled
        case disabled
        case requiresApproval
        case unsupported // running unbundled (no stable bundle identity for SMAppService)

        var isEnabled: Bool {
            self == .enabled
        }
    }

    @Published private(set) var state: State
    @Published var lastErrorMessage: String?

    private static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    init() {
        state = Self.isBundled ? Self.currentState() : .unsupported
    }

    func refresh() {
        guard Self.isBundled else {
            state = .unsupported
            return
        }
        state = Self.currentState()
    }

    func toggle() {
        guard Self.isBundled else { return }
        lastErrorMessage = nil
        do {
            if state.isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettingsLoginItems() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentState() -> State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound, .notRegistered:
            return .disabled
        @unknown default:
            return .disabled
        }
    }
}

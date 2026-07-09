import SwiftUI
import ELAPCore

@main
struct ELAPMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var displayState: DisplayStateModel
    @StateObject private var autoManageEngine: AutoManageEngine
    @StateObject private var loginItemManager = LoginItemManager()
    // Not a @StateObject: holds no observable state, it just needs to outlive the app to keep
    // the global hotkey handler registered.
    private let hotkeyManager: HotkeyManager

    init() {
        if CommandLine.arguments.contains("--version") {
            print("ELAPApp \(elapVersion) (build \(elapBuildNumber))")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)

        let model = DisplayStateModel()
        let engine = AutoManageEngine(displayState: model)
        model.autoManageEngine = engine
        _displayState = StateObject(wrappedValue: model)
        _autoManageEngine = StateObject(wrappedValue: engine)
        // Auto-manage may already be enabled from a prior launch — evaluate immediately
        // rather than waiting for the first callback/poll tick.
        engine.evaluate(displays: model.displays)
        hotkeyManager = HotkeyManager(displayState: model)
    }

    var body: some Scene {
        MenuBarExtra {
            SettingsPanelView()
                .environmentObject(displayState)
                .environmentObject(autoManageEngine)
                .environmentObject(loginItemManager)
        } label: {
            Image(systemName: displayState.builtInIsOn ? "display" : "display.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

// Hard boundary: never strand the user with the built-in display off. If quitting now would
// leave no working screen (built-in off, no real external), re-enable it first — bounded so a
// hung helper process can't block quitting forever.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard wouldStrandUser(displays: fetchDisplays()) else {
            return .terminateNow
        }

        Task {
            _ = try? await withTimeout(seconds: 5) {
                try await ToggleHelper.turnOn()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        return result
    }
}

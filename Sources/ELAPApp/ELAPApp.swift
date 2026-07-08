import SwiftUI
import ELAPCore

@main
struct ELAPMenuBarApp: App {
    init() {
        if CommandLine.arguments.contains("--version") {
            print("ELAPApp \(elapVersion) (build \(elapBuildNumber))")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var displayState = DisplayStateModel()

    var body: some Scene {
        MenuBarExtra {
            SettingsPanelView()
                .environmentObject(displayState)
        } label: {
            Image(systemName: displayState.builtInIsOn ? "display" : "display.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
}

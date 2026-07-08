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

    var body: some Scene {
        MenuBarExtra {
            SettingsPanelView()
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
}

import SwiftUI
import ELAPCore
import KeyboardShortcuts

struct SettingsPanelView: View {
    @EnvironmentObject private var displayState: DisplayStateModel
    @EnvironmentObject private var autoManageEngine: AutoManageEngine
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @AppStorage(AutoManageEngine.enabledDefaultsKey) private var autoManageEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ELAP")
                .font(.headline)

            HStack {
                Text("Built-in display")
                Spacer()
                Text(displayState.builtInIsOn ? "On" : "Off")
                    .foregroundStyle(displayState.builtInIsOn ? .primary : .secondary)
            }
            .font(.subheadline)

            if !displayState.hasRealExternal {
                Text("No external display detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = displayState.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(displayState.builtInIsOn ? "Turn Off" : "Turn On") {
                Task { await displayState.toggleBuiltIn() }
            }
            .disabled(displayState.isBusy || (displayState.builtInIsOn && !displayState.hasRealExternal))

            Divider()

            Toggle("Auto-manage", isOn: $autoManageEnabled)
                .onChange(of: autoManageEnabled) { _ in
                    autoManageEngine.evaluate(displays: displayState.displays)
                }

            if autoManageEngine.daemonConflictDetected {
                Text("The `elap daemon` background watcher is also running and will fight with auto-manage. Run `elap daemon uninstall` or turn off auto-manage here.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            if loginItemManager.state == .unsupported {
                Text("Launch at login requires the bundled app (not `swift run`).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemManager.state.isEnabled },
                    set: { _ in loginItemManager.toggle() }
                ))
                if loginItemManager.state == .requiresApproval {
                    Button("Approve in System Settings…") {
                        loginItemManager.openSystemSettingsLoginItems()
                    }
                    .font(.caption)
                }
                if let message = loginItemManager.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                Text("Hotkey")
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleBuiltInDisplay)
            }

            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }

            Text("\(elapVersion) (build \(elapBuildNumber))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 260)
        .onAppear {
            displayState.refresh()
            displayState.startPolling()
            loginItemManager.refresh()
        }
        .onDisappear {
            displayState.stopPolling()
        }
    }
}

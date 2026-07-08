import SwiftUI
import ELAPCore

struct SettingsPanelView: View {
    @EnvironmentObject private var displayState: DisplayStateModel

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
        }
        .onDisappear {
            displayState.stopPolling()
        }
    }
}

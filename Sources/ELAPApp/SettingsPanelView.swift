import SwiftUI
import ELAPCore

struct SettingsPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ELAP")
                .font(.headline)
            Text("Built-in display toggle coming soon.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }
}

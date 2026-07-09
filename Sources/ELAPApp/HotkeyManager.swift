// ELAPApp — global hotkey to toggle the built-in display from any app.
//
// Persistence and the recorder UI are handled by the KeyboardShortcuts package; this file just
// defines the shortcut name and routes the key event into the same guarded toggle path the
// panel button uses (DisplayStateModel.toggleBuiltIn), so the guard against stranding the user
// applies identically regardless of trigger source.

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBuiltInDisplay = Self("toggleBuiltInDisplay")
}

@MainActor
final class HotkeyManager {
    private weak var displayState: DisplayStateModel?

    init(displayState: DisplayStateModel) {
        self.displayState = displayState
        KeyboardShortcuts.onKeyUp(for: .toggleBuiltInDisplay) { [weak displayState] in
            Task { await displayState?.toggleBuiltIn() }
        }
    }
}

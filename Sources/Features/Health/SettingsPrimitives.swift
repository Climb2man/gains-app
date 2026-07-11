import SwiftUI

/// Subtle press tint for grouped settings rows, without a global list style. Used by `SettingsNavRow`.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.Colors.surface2 : Color.clear)
    }
}

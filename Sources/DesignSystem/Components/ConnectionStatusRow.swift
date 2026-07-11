import SwiftUI

struct ConnectionStatusRow: View {
    enum State {
        /// Not yet connected. A primary action button that runs `action`.
        case connect(label: String, action: () -> Void)
        /// A two-way integration is linked (Whoop, scale). Soft-success surface + animated checkmark.
        case linked
        /// A value/record was just persisted. Soft-success surface + animated checkmark.
        case saved
        /// Requested and pending. Neutral surface, never green: a read-only HealthKit grant
        /// can't be asserted as "connected" under Apple's privacy semantics.
        case requested
        /// The integration isn't available on this device/account; shows the provided reason, muted.
        case unavailable(String)
    }

    let title: String
    let systemImage: String
    let state: State

    /// Fire a success haptic when a `.linked`/`.saved` row first appears. Off by default so a
    /// list of already-linked rows doesn't buzz on every render.
    var hapticOnAppear: Bool = false

    init(title: String, systemImage: String, state: State, hapticOnAppear: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.state = state
        self.hapticOnAppear = hapticOnAppear
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            leadingIcon

            Text(title)
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(titleColor)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.sm)

            trailing
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(rowSurface)
    }

    private var leadingIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case let .connect(label, action):
            AppButton(title: label, kind: .primary, action: action)
                .fixedSize()

        case .linked, .saved:
            CheckmarkStatus(reduceMotion: reduceMotion, hapticOnAppear: hapticOnAppear)

        case .requested:
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                Text("Requested")
                    .font(Theme.Font.subhead.weight(.medium))
            }
            .foregroundStyle(Theme.Colors.labelSecondary)

        case let .unavailable(reason):
            Text(reason)
                .font(Theme.Font.subhead)
                .foregroundStyle(Theme.Colors.labelTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var rowSurface: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md)
        switch state {
        case .linked, .saved:
            return shape.fill(Theme.Colors.successSoft)
        case .requested:
            return shape.fill(Theme.Colors.fieldBackground)
        case .connect, .unavailable:
            return shape.fill(Color.clear)
        }
    }

    private var iconColor: Color {
        switch state {
        case .linked, .saved: return Theme.Colors.success
        case .requested: return Theme.Colors.labelSecondary
        case .unavailable: return Theme.Colors.labelTertiary
        case .connect: return Theme.Colors.tint
        }
    }

    private var titleColor: Color {
        switch state {
        case .unavailable: return Theme.Colors.labelTertiary
        default: return Theme.Colors.label
        }
    }
}

private struct CheckmarkStatus: View {
    let reduceMotion: Bool
    let hapticOnAppear: Bool

    @SwiftUI.State private var appeared = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.Colors.success)
            .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? .default : nil, value: appeared)
            .onAppear {
                appeared = true
                if hapticOnAppear {
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
            }
    }
}

#if DEBUG
#Preview("ConnectionStatusRow") {
    ScrollView {
        VStack(spacing: Theme.Spacing.md) {
            ConnectionStatusRow(
                title: "Whoop",
                systemImage: "bolt.heart",
                state: .connect(label: "Connect") {}
            )
            ConnectionStatusRow(
                title: "Whoop",
                systemImage: "bolt.heart",
                state: .linked,
                hapticOnAppear: true
            )
            ConnectionStatusRow(
                title: "Body weight",
                systemImage: "scalemass",
                state: .saved
            )
            ConnectionStatusRow(
                title: "Apple Health",
                systemImage: "heart.text.square",
                state: .requested
            )
            ConnectionStatusRow(
                title: "Apple Watch",
                systemImage: "applewatch",
                state: .unavailable("Not paired with this iPhone")
            )
        }
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
#endif

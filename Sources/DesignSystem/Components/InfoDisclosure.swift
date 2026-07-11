import SwiftUI

struct InfoDisclosure: View {
    let title: String?
    let message: String

    init(title: String? = nil, body: String) {
        self.title = title
        self.message = body
    }

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(Theme.Font.subhead)
                .foregroundStyle(Theme.Colors.labelTertiary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? "More information")
        .accessibilityHint("Shows an explanation")
        .sheet(isPresented: $isPresented) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let title {
                        Text(title)
                            .font(Theme.Font.bodyEmphasized)
                            .foregroundStyle(Theme.Colors.label)
                    }
                    Text(message)
                        .font(Theme.Font.subhead)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.xl)
            }
            .presentationDetents([.height(280), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        HStack(spacing: Theme.Spacing.sm) {
            Text("Resting heart rate")
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Colors.label)
            InfoDisclosure(
                title: "vs your typical",
                body: "This compares today's reading to your own recent baseline, not to a "
                    + "population. It's context on how today sits against your usual."
            )
        }
    }
}
#endif

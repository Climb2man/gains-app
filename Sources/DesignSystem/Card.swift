import SwiftUI

struct Card<Content: View>: View {
    var elevated: Bool = false
    var metricAccent: Color? = nil
    @ViewBuilder var content: Content

    private var shadowStyle: Theme.Shadow.Style {
        elevated ? Theme.Shadow.cardElevated : Theme.Shadow.card
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape
                .fill(Theme.Colors.surface)
                .overlay(alignment: .top) {
                    if let metricAccent {
                        LinearGradient(
                            colors: [metricAccent.opacity(0.9), Theme.Chart.light(metricAccent)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 3)
                    }
                }
                .clipShape(shape)
        }
        .overlay { shape.stroke(Color.black.opacity(0.06), lineWidth: 1) }
        .compositingGroup()
        .cardShadow(shadowStyle)
    }
}

#if DEBUG
#Preview("Card variants") {
    ScrollView {
        VStack(spacing: Theme.Spacing.lg) {
            Card {
                Txt("Resting card", variant: .bodyEmphasized)
                Txt("Low two-tier shadow, 20pt continuous corner, hairline edge.",
                    variant: .footnote, color: .labelSecondary)
            }
            Card(elevated: true) {
                Txt("Elevated / hero card", variant: .bodyEmphasized)
                Txt("Floats a touch more for the screen's primary surface.",
                    variant: .footnote, color: .labelSecondary)
            }
            Card(metricAccent: Theme.Chart.recovery) {
                Txt("Recovery", variant: .footnote, color: .labelSecondary)
                Text("87")
                    .font(Theme.Font.heroNumber)
                    .foregroundStyle(Theme.Colors.label)
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
#endif

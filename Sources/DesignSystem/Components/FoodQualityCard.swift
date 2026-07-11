import SwiftUI

struct FoodQualityCard: View {
    /// One food-quality row: a label, a 0…1 meter level, and a descriptive caption.
    struct Item: Identifiable {
        let label: String
        /// 0…1 meter fill, clamped on display.
        let score: Double
        let descriptor: String
        var id: String { label }
    }

    let items: [Item]

    /// Tuple-based init for concise call sites.
    init(items: [(label: String, score: Double, descriptor: String)]) {
        self.items = items.map { Item(label: $0.label, score: $0.score, descriptor: $0.descriptor) }
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Chart.activity)
                    Text("Food qualities")
                        .font(Theme.Font.footnote.weight(.semibold))
                        .tracking(0.3)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .textCase(.uppercase)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    QualityRow(item: item)
                    if index < items.count - 1 {
                        Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct QualityRow: View {
    let item: FoodQualityCard.Item

    private var level: Double { min(1, max(0, item.score)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(item.label)
                    .font(Theme.Font.subhead.weight(.medium))
                    .foregroundStyle(Theme.Colors.label)
                Spacer(minLength: 0)
            }
            QualityMeter(level: level)
            Text(item.descriptor)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label). \(item.descriptor)")
    }
}

/// Capsule meter in the activity hue.
/// Grows in from 0 on appear (instant under Reduce Motion).
private struct QualityMeter: View {
    let level: Double
    var height: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var drawn: Double { (shown || reduceMotion) ? level : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.fieldBackground)
                Capsule()
                    .fill(LinearGradient(
                        colors: Theme.Chart.gradientStops(for: Theme.Chart.activity),
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * CGFloat(drawn))
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true }
        }
    }
}

#if DEBUG
#Preview("FoodQualityCard") {
    FoodQualityCard(items: [
        (label: "Protein density", score: 0.82,
         descriptor: "High protein for the calories vs your typical day."),
        (label: "Fiber", score: 0.4,
         descriptor: "A little below your usual fiber for this many calories."),
        (label: "Added sugar", score: 0.25,
         descriptor: "Lower added sugar than most of your logged days."),
    ])
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif

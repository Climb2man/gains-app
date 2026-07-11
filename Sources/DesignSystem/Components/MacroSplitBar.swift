import SwiftUI

struct MacroSplitBar: View {
    let proteinG: Int
    let fatG: Int
    let carbsG: Int

    /// Bar thickness.
    var height: CGFloat = 14
    /// Show the dot + grams legend beneath the bar (default true).
    var showLegend: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var proteinCals: Double { Double(max(0, proteinG)) * 4 }
    private var fatCals: Double { Double(max(0, fatG)) * 9 }
    private var carbsCals: Double { Double(max(0, carbsG)) * 4 }
    private var totalCals: Double { proteinCals + fatCals + carbsCals }

    private struct Slice {
        let cals: Double
        let grams: Int
        let color: Color
        let label: String
    }

    private var slices: [Slice] {
        [
            Slice(cals: proteinCals, grams: proteinG, color: Theme.Chart.protein, label: "Protein"),
            Slice(cals: fatCals, grams: fatG, color: Theme.Chart.fat, label: "Fat"),
            Slice(cals: carbsCals, grams: carbsG, color: Theme.Chart.carbs, label: "Carbs"),
        ]
    }

    private var drawable: [Slice] { slices.filter { $0.cals > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GeometryReader { geo in
                let gap: CGFloat = drawable.count > 1 ? 2 : 0
                let gapTotal = gap * CGFloat(max(0, drawable.count - 1))
                let usable = max(0, geo.size.width - gapTotal)
                HStack(spacing: gap) {
                    ForEach(drawable.indices, id: \.self) { i in
                        let slice = drawable[i]
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: totalCals > 0 ? usable * (slice.cals / totalCals) : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(Theme.Colors.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: totalCals)
            .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: proteinCals)
            .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: fatCals)

            if showLegend {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(slices.indices, id: \.self) { i in
                        legendItem(slices[i])
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Macro split: protein \(proteinG) grams, fat \(fatG) grams, carbs \(carbsG) grams")
    }

    private func legendItem(_ slice: Slice) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle().fill(slice.color).frame(width: 8, height: 8)
            Text(slice.label)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Colors.labelSecondary)
            Text("\(max(0, slice.grams))g")
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.label)
                .contentTransition(.numericText())
        }
    }
}

#if DEBUG
#Preview("MacroSplitBar") {
    VStack(spacing: Theme.Spacing.xl) {
        MacroSplitBar(proteinG: 160, fatG: 73, carbsG: 206)
        MacroSplitBar(proteinG: 200, fatG: 60, carbsG: 120)
        MacroSplitBar(proteinG: 0, fatG: 0, carbsG: 0)
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif

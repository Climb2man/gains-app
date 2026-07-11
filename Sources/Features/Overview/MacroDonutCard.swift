import SwiftUI

struct MacroDonutCard: View {
    let totals: DailyTotals
    /// Header label (e.g. "MACROS" for today, "MACROS · MON 3" for a scoped past day).
    var title: String = "MACROS"
    /// Deep-link into the Calories tab.
    var onPress: (() -> Void)?

    private let kcalPerProteinG = 4.0
    private let kcalPerCarbG = 4.0
    private let kcalPerFatG = 9.0

    private struct Macro: Identifiable {
        let key: String
        let label: String
        let grams: Double
        let cals: Double
        let color: Color
        var id: String { key }
    }

    private var macros: [Macro] {
        [
            Macro(key: "protein", label: "Protein", grams: totals.proteinG,
                  cals: totals.proteinG * kcalPerProteinG, color: Theme.Chart.protein),
            Macro(key: "carbs", label: "Carbs", grams: totals.carbsG,
                  cals: totals.carbsG * kcalPerCarbG, color: Theme.Chart.carbs),
            Macro(key: "fat", label: "Fat", grams: totals.fatG,
                  cals: totals.fatG * kcalPerFatG, color: Theme.Chart.fat),
        ]
    }

    private var totalCals: Double { macros.reduce(0) { $0 + $1.cals } }
    private var hasData: Bool { totalCals > 0 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        Card(metricAccent: Theme.Chart.protein) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                CardHeader(title: title, icon: "fork.knife")

                HStack(spacing: Theme.Spacing.xl) {
                    ZStack {
                        DonutChart(
                            segments: macros.map { DonutSegment(value: $0.cals, color: $0.color, label: $0.label) },
                            size: 128,
                            strokeWidth: 16
                        )
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
                        .opacity(appeared || reduceMotion ? 1 : 0)

                        VStack(spacing: 2) {
                            Text(hasData ? Format.int(totalCals) : "–")
                                .font(Theme.Font.statNumber)
                                .monospacedDigit()
                                .contentTransition(reduceMotion ? .identity : .numericText())
                                .foregroundStyle(Theme.Colors.label)
                            Text(hasData ? "kcal" : "no food yet")
                                .font(Theme.Font.footnote)
                                .foregroundStyle(Theme.Colors.labelSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(macros) { macro in
                            legendRow(macro)
                        }
                    }
                }

                if !hasData {
                    Txt("Log a meal to see the macro split.", variant: .footnote, color: .labelTertiary)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
        }
    }

    private func legendRow(_ macro: Macro) -> some View {
        let pct = totalCals > 0 ? Int((macro.cals / totalCals * 100).rounded()) : 0
        return HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(macro.color).frame(width: 10, height: 10)
            Txt(macro.label, variant: .subhead)
            Spacer(minLength: 0)
            Txt("\(Format.int(macro.grams)) g · \(pct)%", variant: .subhead, color: .labelSecondary)
        }
    }
}

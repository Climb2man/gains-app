#if DEBUG
import SwiftUI

struct CalorieMockupsCanvas: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text("Calorie header")
                    .font(Theme.Font.title2).foregroundStyle(Theme.Colors.label)
                    .padding(.top, Theme.Spacing.sm)

                option("One ring + macro bars", "macro totals shown as bars under the ring") {
                    MockA()
                }
                option("Calorie ring + 3 macro rings", "each macro shown as its own ring") {
                    MockB()
                }
                option("Two big circles", "calorie ring beside a macro donut") {
                    MockC()
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.background)
    }

    private func option<V: View>(_ title: String, _ note: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(Theme.Font.footnote.weight(.bold)).foregroundStyle(Theme.Colors.tint)
            Text(note)
                .font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
            content()
        }
    }
}

private enum Mock {
    static let eaten = 1580.0, goal = 2800.0
    static var leftFrac: Double { eaten / goal }
    static let p = (v: 120, g: 200), c = (v: 160, g: 300), f = (v: 49, g: 78)
}

private struct MockA: View {
    var body: some View {
        Card(metricAccent: Theme.Chart.calories) {
            VStack(spacing: Theme.Spacing.lg) {
                RingChart(progress: Mock.leftFrac, size: 138, strokeWidth: 15,
                          color: Theme.Chart.calories, glow: false,
                          centerLabel: "1,220", centerSubLabel: "kcal left")
                VStack(spacing: Theme.Spacing.md) {
                    macroBar("Protein", Mock.p.v, Mock.p.g, Theme.Chart.protein)
                    macroBar("Carbs", Mock.c.v, Mock.c.g, Theme.Chart.carbs)
                    macroBar("Fat", Mock.f.v, Mock.f.g, Theme.Chart.fat)
                }
            }
        }
    }

    private func macroBar(_ label: String, _ value: Int, _ goal: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelSecondary)
                Spacer()
                Text("\(value) / \(goal) g").font(Theme.Font.statNumber.weight(.regular))
                    .foregroundStyle(Theme.Colors.label)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.fieldBackground)
                    Capsule()
                        .fill(LinearGradient(colors: Theme.Chart.gradientStops(for: color),
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(1, Double(value) / Double(goal)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct MockB: View {
    var body: some View {
        Card(metricAccent: Theme.Chart.calories) {
            VStack(spacing: Theme.Spacing.lg) {
                RingChart(progress: Mock.leftFrac, size: 120, strokeWidth: 13,
                          color: Theme.Chart.calories, glow: false,
                          centerLabel: "1,220", centerSubLabel: "kcal left")
                HStack(spacing: Theme.Spacing.md) {
                    StatRingCard(label: "Protein", value: "120g", percent: "60%", progress: 0.60, color: Theme.Chart.protein)
                    StatRingCard(label: "Carbs", value: "160g", percent: "53%", progress: 0.53, color: Theme.Chart.carbs)
                    StatRingCard(label: "Fat", value: "49g", percent: "63%", progress: 0.63, color: Theme.Chart.fat)
                }
            }
        }
    }
}

private struct MockC: View {
    var body: some View {
        Card(metricAccent: Theme.Chart.calories) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                RingChart(progress: Mock.leftFrac, size: 124, strokeWidth: 14,
                          color: Theme.Chart.calories, glow: false,
                          centerLabel: "1,220", centerSubLabel: "left")
                Spacer(minLength: 0)
                VStack(spacing: Theme.Spacing.sm) {
                    MacroDonut(
                        segments: [
                            (value: Double(Mock.p.v) * 4, color: Theme.Chart.protein, label: "Protein"),
                            (value: Double(Mock.c.v) * 4, color: Theme.Chart.carbs, label: "Carbs"),
                            (value: Double(Mock.f.v) * 9, color: Theme.Chart.fat, label: "Fat"),
                        ],
                        size: 110, strokeWidth: 13, centerLabel: "1,580", centerSubLabel: "kcal")
                    legend
                }
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            dot("Protein", "120g", Theme.Chart.protein)
            dot("Carbs", "160g", Theme.Chart.carbs)
            dot("Fat", "49g", Theme.Chart.fat)
        }
    }

    private func dot(_ label: String, _ grams: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelSecondary)
            Text(grams).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.label)
        }
    }
}
#endif

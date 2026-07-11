import SwiftUI

struct MacroProgressCard: View {
    /// One macro row's data: name, current grams, goal grams, and the light→base gradient stops.
    struct Macro: Identifiable {
        let label: String
        let grams: Double
        let goal: Double
        let gradient: [Color]
        var id: String { label }
    }

    /// One optional micronutrient row: label + a pre-formatted value (e.g. "44 g", "2,100 mg").
    struct Micro: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let macros: [Macro]
    var micros: [Micro] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(macros) { macro in
                MacroRow(macro: macro)
            }
            if !micros.isEmpty {
                HStack(spacing: Theme.Spacing.xl) {
                    ForEach(micros) { micro in
                        MicroRow(micro: micro)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MacroRow: View {
    let macro: MacroProgressCard.Macro

    private var progress: Double { macro.goal > 0 ? macro.grams / macro.goal : 0 }
    private var over: Bool { macro.goal > 0 && macro.grams > macro.goal }
    /// Over-goal bars swap to a warning ramp; otherwise the macro's own light→base stops.
    private var stops: [Color] {
        over ? Theme.Chart.gradientStops(for: Theme.Colors.warning) : macro.gradient
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.label.uppercased())
                    .font(Theme.Font.footnote)
                    .tracking(0.5)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                Spacer(minLength: Theme.Spacing.sm)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Format.int(macro.grams))")
                        .font(Theme.Font.statNumber)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(over ? Theme.Colors.warning : Theme.Colors.label)
                    Text("/ \(Format.int(macro.goal)) g")
                        .font(Theme.Font.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
            }
            MacroGradientBar(progress: progress, stops: stops)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(macro.label) \(Format.int(macro.grams)) of \(Format.int(macro.goal)) grams"
                + (over ? ", over goal" : "")
        )
    }
}

private struct MicroRow: View {
    let micro: MacroProgressCard.Micro

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(micro.label.uppercased())
                .font(Theme.Font.footnote)
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.labelTertiary)
            Text(micro.value)
                .font(Theme.Font.inlineNumber)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(micro.label) \(micro.value)")
    }
}

/// Capsule track with a gradient fill scaled to clamped progress; grows in from 0 on appear
/// (instant under Reduce Motion). Local because `ProgressBar` is a flat solid fill without the gradient.
private struct MacroGradientBar: View {
    let progress: Double
    let stops: [Color]
    var height: CGFloat = 8

    private var clamped: Double { min(1, max(0, progress)) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var drawn: Double { (shown || reduceMotion) ? clamped : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.fieldBackground)
                Capsule()
                    .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(drawn))
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true }
        }
        .onChange(of: clamped) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true }
        }
    }
}

#if DEBUG
#Preview("MacroProgressCard") {
    VStack(spacing: Theme.Spacing.xl) {
        MacroProgressCard(
            macros: [
                .init(label: "Protein", grams: 132, goal: 160, gradient: Theme.Chart.proteinGradient),
                .init(label: "Carbs", grams: 180, goal: 206, gradient: Theme.Chart.carbsGradient),
                .init(label: "Fat", grams: 84, goal: 73, gradient: Theme.Chart.fatGradient),
            ],
            micros: [
                .init(label: "Sugar", value: "44 g"),
                .init(label: "Fiber", value: "22 g"),
            ]
        )
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.surface)
}
#endif

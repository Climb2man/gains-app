import SwiftUI

/// Whoop's measured whole-day burn against the TDEE the goal formula computes from weight.
///
/// This card is deliberately READ-ONLY and changes no targets. Calories and macros are still
/// derived from `GoalCalculator` (BMR × activity factor × goal multiplier); this only shows how far
/// that estimate sits from what Whoop actually recorded, so the activity band — the one input in the
/// model that is a self-assessment rather than a measurement — can be sanity-checked against data.
///
/// The two numbers are genuinely comparable: Whoop's `calories` is whole-day expenditure including
/// BMR, which is what TDEE means. It is not the "active calories" slice, which would be an
/// apples-to-oranges comparison and badly misleading here.
struct TdeeCompareCard: View {
    @Environment(AppModel.self) private var appModel

    /// Complete days averaged. Matches the strain window used to suggest an activity band.
    private let windowDays = 7

    @State private var measured: (mean: Double, sampleCount: Int)?
    @State private var loaded = false

    /// Percent Whoop's measurement sits above (+) or below (−) the formula's estimate.
    private var deltaPct: Double? {
        guard let measured, let formula = appModel.formulaTdee, formula > 0 else { return nil }
        return (measured.mean - Double(formula)) / Double(formula) * 100
    }

    var body: some View {
        // Nothing to compare against without Whoop; the card simply does not apply.
        if appModel.whoopLinked {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    CardHeader(title: "TDEE CHECK", icon: "arrow.left.arrow.right")
                    content
                }
            }
            .task {
                measured = await appModel.whoopCalorieAverage(days: windowDays)
                loaded = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appModel.formulaTdee == nil {
            // The formula half needs a saved goal recipe. Say which half is missing.
            Txt("Save a goal in Goals and this will compare it against what WHOOP measured.",
                variant: .footnote, color: .labelSecondary)
        } else if !loaded {
            ProgressView().controlSize(.small)
        } else if let measured, let formula = appModel.formulaTdee, let deltaPct {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                row(
                    title: "WHOOP measured",
                    detail: "\(measured.sampleCount)-day average, whole-day burn",
                    // Plain white: this one is a recorded fact. The formula's number is tinted
                    // below to mark it as computed. (Theme.Chart.strain aliases the tint, so it
                    // could not carry that distinction here.)
                    value: measured.mean,
                    accent: Theme.Colors.label
                )
                Divider().overlay(Theme.Colors.separator)
                row(
                    title: "Formula",
                    detail: formulaDetail,
                    value: Double(formula),
                    accent: Theme.Colors.tint
                )
                delta(deltaPct)
            }
        } else {
            Txt("Not enough complete WHOOP days yet — this needs at least 4. Today is left out "
                + "because it is still being recorded.",
                variant: .footnote, color: .labelSecondary)
        }
    }

    /// Names the activity band the formula assumed, since that is the input this card is really
    /// testing and the one the user can change.
    private var formulaDetail: String {
        guard let activity = appModel.goalActivity else { return "from your weight" }
        return "\(activity.label) · \(activity.hoursPerWeek)"
    }

    private func row(title: String, detail: String, value: Double, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Txt(title, variant: .subhead, color: .label)
                Txt(detail, variant: .footnote, color: .labelTertiary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.formatted(.number.precision(.fractionLength(0))))
                    .font(Theme.Font.statNumber)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Txt("cal", variant: .footnote, color: .labelTertiary)
            }
        }
    }

    private func delta(_ pct: Double) -> some View {
        let magnitude = abs(pct)
        let higher = pct > 0
        // A gap here is not an error, it is a mis-set activity band — which is worth escalating
        // visually as it widens, because it silently skews every calorie target.
        let tone: Color = magnitude < 5 ? Theme.Colors.success
            : magnitude < 15 ? Theme.Colors.warning
            : Theme.Colors.danger

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: magnitude < 5 ? "equal.circle.fill"
                    : higher ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(tone)
                Text("\(Format.oneDecimal(magnitude))% \(higher ? "higher" : "lower")")
                    .font(Theme.Font.subhead.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                Txt("than the formula", variant: .footnote, color: .labelTertiary)
            }
            Txt(interpretation(pct), variant: .footnote, color: .labelSecondary)
            Txt("Your targets still come from the formula. This is a check, not a change.",
                variant: .footnote, color: .labelTertiary)
        }
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "WHOOP measured \(Format.oneDecimal(magnitude)) percent "
            + "\(higher ? "higher" : "lower") than the formula"
        )
    }

    private func interpretation(_ pct: Double) -> String {
        let magnitude = abs(pct)
        if magnitude < 5 {
            return "Close match — the activity level you picked lines up with what WHOOP records."
        }
        if pct > 0 {
            return "WHOOP records more burn than your activity level assumes. Moving up a band in "
                + "Goals would close the gap."
        }
        return "WHOOP records less burn than your activity level assumes. Moving down a band in "
            + "Goals would close the gap."
    }
}

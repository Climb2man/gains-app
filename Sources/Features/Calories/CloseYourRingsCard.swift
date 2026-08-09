import SwiftUI

/// "What should I eat now?" — foods from the user's own history, ranked by how well each closes
/// what is left of today's calorie and macro targets.
///
/// Candidates are saved meals and recent entries only. Suggesting a food the user has never logged
/// would be a recipe recommendation, which is a different product and needs ingredients they may not
/// have; suggesting one they ate last Tuesday is actionable now. It also costs nothing and works
/// with no OpenRouter key and no network.
struct CloseYourRingsCard: View {
    let totals: FoodDayTotals
    let goals: Goals
    let candidates: [MacroGapRecommender.Candidate]
    /// Log the chosen food straight into today.
    var onLog: ((MacroGapRecommender.Candidate) -> Void)?

    /// Routed through the shared helper rather than subtracting inline, so this and the Overview
    /// side cannot drift apart. `FoodDayTotals` carries extras (sugar, fibre, sodium, water) the
    /// recommender has no opinion on, so only the four it uses are mapped across.
    private var gap: MacroGapRecommender.Gap {
        MacroGapRecommender.gap(
            goals: goals,
            totals: DailyTotals(
                calories: totals.calories,
                proteinG: totals.proteinG,
                carbsG: totals.carbsG,
                fatG: totals.fatG
            )
        )
    }

    private var suggestions: [MacroGapRecommender.Suggestion] {
        MacroGapRecommender.rank(candidates: candidates, gap: gap, limit: 3)
    }

    var body: some View {
        Card(metricAccent: Theme.Chart.calories) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                CardHeader(title: "CLOSE YOUR RINGS", icon: "target")

                if goals.calorieGoal <= 0 {
                    Txt("Set a goal and this will suggest what to eat next.",
                        variant: .footnote, color: .labelTertiary)
                } else if gap.isClosed {
                    Txt("Today's targets are met. Nothing more needed.",
                        variant: .body, color: .labelSecondary)
                } else if candidates.isEmpty {
                    Txt("Log a few meals and save the ones you repeat — suggestions come from foods "
                        + "you've eaten before.",
                        variant: .footnote, color: .labelTertiary)
                } else if suggestions.isEmpty {
                    Txt("Nothing you've logged before fits what's left "
                        + "(\(Format.int(max(0, gap.calories))) calories).",
                        variant: .footnote, color: .labelTertiary)
                } else {
                    remainingLine
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionRow(suggestion)
                        if index < suggestions.count - 1 { HairlineDivider() }
                    }
                }
            }
        }
    }

    /// States the gap the suggestions are trying to close, so the list has visible reasoning behind
    /// it rather than appearing to be arbitrary picks.
    private var remainingLine: some View {
        Txt("Left today: \(Format.int(max(0, gap.calories))) calories · "
            + "\(Format.int(max(0, gap.proteinG))) grams protein · "
            + "\(Format.int(max(0, gap.carbsG))) grams carbs · "
            + "\(Format.int(max(0, gap.fatG))) grams fat",
            variant: .footnote, color: .labelTertiary)
    }

    private func suggestionRow(_ s: MacroGapRecommender.Suggestion) -> some View {
        let c = s.candidate
        return Button { onLog?(c) } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Txt(c.name, variant: .bodyEmphasized)
                        if s.overshoots {
                            Txt("goes over", variant: .footnote, color: .warning)
                        }
                    }
                    Txt("\(Format.int(c.calories)) calories", variant: .footnote, color: .labelTertiary)
                    Txt("\(Format.int(c.proteinG)) grams protein · "
                        + "\(Format.int(c.carbsG)) grams carbs · "
                        + "\(Format.int(c.fatG)) grams fat",
                        variant: .footnote, color: .labelTertiary)
                }
                Spacer(minLength: 0)
                if onLog != nil {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Chart.calories)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.name), \(Format.int(c.calories)) calories")
        .accessibilityHint(onLog == nil ? "" : "Logs this food for today")
    }
}

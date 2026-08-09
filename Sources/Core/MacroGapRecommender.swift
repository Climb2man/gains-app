import Foundation

/// Ranks foods you already eat by how well they close the rest of today's rings.
///
/// Deliberately deterministic and offline: the candidates are the user's own saved meals and recent
/// entries, so a suggestion is always something they have eaten before and can actually get hold of.
/// No AI call, no network, no cost, and it works with the OpenRouter key absent.
enum MacroGapRecommender {

    /// A food that could be logged. Flat on purpose so saved meals and past entries can both map in.
    struct Candidate: Equatable, Sendable {
        var id: String
        var name: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
    }

    /// What is still owed today. Components may be <= 0 when a target is already met or passed.
    struct Gap: Equatable, Sendable {
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double

        /// Nothing meaningful left to close.
        var isClosed: Bool {
            calories <= 0 && proteinG <= 0 && carbsG <= 0 && fatG <= 0
        }
    }

    struct Suggestion: Equatable, Sendable, Identifiable {
        var id: String { candidate.id }
        var candidate: Candidate
        /// Lower is better. Exposed so the UI can dim weak matches rather than pretending they fit.
        var score: Double
        /// True when logging this would take any target past its goal.
        var overshoots: Bool
    }

    /// Grams are compared in CALORIES, not grams, so a gram of fat is not weighed the same as a gram
    /// of carbohydrate. Without this a fat-heavy food looks like a small miss when it is a large one.
    private static let kcalPerProteinG = 4.0
    private static let kcalPerCarbG = 4.0
    private static let kcalPerFatG = 9.0

    /// Overshooting is penalised harder than falling short. Eating 200 kcal too few still leaves you
    /// somewhere useful; 200 kcal too many cannot be undone, and on a cut that is the failure mode
    /// that matters.
    private static let overshootPenalty = 2.2

    /// Protein is weighted above the other two. On a cut it is the target people miss and the one
    /// worth protecting, and it is also the hardest to make up late in the day.
    private static let proteinWeight = 1.6
    private static let carbWeight = 1.0
    private static let fatWeight = 1.0
    private static let calorieWeight = 1.3

    /// Rank candidates by how close each leaves the day to its targets.
    ///
    /// Returns at most `limit`, best first. Candidates that would blow the calorie budget by more
    /// than `tolerance` are dropped outright rather than ranked low: a suggestion that ruins the day
    /// is not a weak suggestion, it is the wrong answer.
    static func rank(
        candidates: [Candidate],
        gap: Gap,
        limit: Int = 3,
        calorieOvershootTolerance: Double = 120
    ) -> [Suggestion] {
        guard !gap.isClosed else { return [] }

        let scored: [Suggestion] = candidates.compactMap { candidate in
            guard candidate.calories > 0 else { return nil }
            // Hard filter: too big for what's left.
            if candidate.calories > gap.calories + calorieOvershootTolerance { return nil }

            let residualCals = gap.calories - candidate.calories
            let residualProtein = (gap.proteinG - candidate.proteinG) * kcalPerProteinG
            let residualCarb = (gap.carbsG - candidate.carbsG) * kcalPerCarbG
            let residualFat = (gap.fatG - candidate.fatG) * kcalPerFatG

            let score = cost(residualCals) * calorieWeight
                + cost(residualProtein) * proteinWeight
                + cost(residualCarb) * carbWeight
                + cost(residualFat) * fatWeight

            let overshoots = residualCals < 0 || residualProtein < 0
                || residualCarb < 0 || residualFat < 0

            return Suggestion(candidate: candidate, score: score, overshoots: overshoots)
        }

        return scored
            // Ties broken by name so the list is stable between renders rather than reshuffling.
            .sorted { $0.score == $1.score ? $0.candidate.name < $1.candidate.name : $0.score < $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Distance from target for one component, asymmetric: over costs more than under.
    private static func cost(_ residual: Double) -> Double {
        residual >= 0 ? residual : -residual * overshootPenalty
    }

    /// Today's remaining targets. Components are allowed to go negative so an already-passed target
    /// pushes suggestions away from that macro instead of being treated as "no preference".
    static func gap(goals: Goals, totals: DailyTotals) -> Gap {
        Gap(
            calories: goals.calorieGoal - totals.calories,
            proteinG: goals.proteinGoal - totals.proteinG,
            carbsG: goals.carbGoal - totals.carbsG,
            fatG: goals.fatGoal - totals.fatG
        )
    }
}

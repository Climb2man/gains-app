import Foundation

/// Calorie + macro targets via the Bigger Leaner Stronger method (Matthews, ch. 17).
///
/// Pipeline: BMR (Mifflin–St Jeor) → TDEE (BMR × activity) → goal calories (% of TDEE) → macros
/// (% split of goal calories).
///
/// This replaced a calculator.net-style model that used fixed kcal deltas (−500 for "lose 1 lb/week")
/// and derived protein/fat from body weight alone. Two consequences of the change:
///
///   * A percentage deficit scales with body size where a fixed delta does not.
///   * Macros now derive FROM the calorie goal, so they always sum to it. The old model computed
///     protein and fat from body weight independently of calories, which on a small frame with an
///     aggressive deficit produced targets that could not physically fit the day and needed a
///     rescaling workaround. That whole class of bug is gone.
///
/// Deliberately NOT implemented: the book's cal/lb sanity bands (10–12 cut, 14–16 maintain,
/// 16–18 bulk) and the g/lb shortcut table. The shortcut disagrees with the percentage split by
/// ~130 kcal/day, and only one method can be authoritative.
enum GoalCalculator {
    private static let kcalPerProteinG: Double = 4
    private static let kcalPerCarbG: Double = 4
    private static let kcalPerFatG: Double = 9

    /// Activity keyed to HOURS OF EXERCISE PER WEEK, which is the book's axis (the previous model
    /// used days/week from calculator.net and ran ~5% higher across the board).
    ///
    /// The book gives ranges rather than single multipliers; each `factor` is the midpoint of its
    /// range, so one number drives the maths and the range is shown to the user as context.
    enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
        case sedentary, light, moderate, veryActive, extraActive

        var id: String { rawValue }

        /// BMR × factor = TDEE. Midpoint of the book's range for the band.
        var factor: Double {
            switch self {
            case .sedentary: return 1.15    // book: 1.15 flat
            case .light: return 1.275       // book: 1.2–1.35
            case .moderate: return 1.475    // book: 1.4–1.55
            case .veryActive: return 1.675  // book: 1.6–1.75
            case .extraActive: return 1.875 // book: 1.8–1.95
            }
        }

        var label: String {
            switch self {
            case .sedentary: return "Sedentary"
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .veryActive: return "Very active"
            case .extraActive: return "Extra active"
            }
        }

        /// The defining hours-per-week band, shown beside the label so the choice is unambiguous.
        var hoursPerWeek: String {
            switch self {
            case .sedentary: return "0 hrs/week"
            case .light: return "1–3 hrs/week"
            case .moderate: return "4–6 hrs/week"
            case .veryActive: return "7–9 hrs/week"
            case .extraActive: return "10+ hrs/week"
            }
        }

        var description: String {
            switch self {
            case .sedentary: return "No exercise"
            case .light: return "Light exercise or sport"
            case .moderate: return "Regular training"
            case .veryActive: return "Hard training most days"
            case .extraActive: return "Athlete or physical job"
            }
        }
    }

    /// The three goals. Calorie target is a percentage of TDEE, and each goal carries its own macro
    /// split — unlike the previous model, where the split was identical whatever the goal.
    enum GoalDirection: String, CaseIterable, Identifiable, Sendable {
        case cut, maintain, leanBulk

        var id: String { rawValue }

        /// Goal calories = TDEE × this.
        ///
        /// The book's reasoning: 25% is the aggressive-but-not-reckless deficit — halving it to
        /// 10–12% halves weekly fat loss and doubles the diet's length, which is what makes people
        /// quit. On the bulk side 110% is the point of diminishing returns; 120–130% adds fat rather
        /// than extra muscle.
        var tdeeMultiplier: Double {
            switch self {
            case .cut: return 0.75
            case .maintain: return 1.0
            case .leanBulk: return 1.10
            }
        }

        var label: String {
            switch self {
            case .cut: return "Cut"
            case .maintain: return "Maintain"
            case .leanBulk: return "Lean bulk"
            }
        }

        var description: String {
            switch self {
            case .cut: return "25% below maintenance"
            case .maintain: return "At maintenance"
            case .leanBulk: return "10% above maintenance"
            }
        }

        /// Fraction of goal calories from each macro. Sums to 1.0 for every case.
        var macroSplit: (protein: Double, carb: Double, fat: Double) {
            switch self {
            case .cut: return (0.40, 0.40, 0.20)
            case .maintain: return (0.30, 0.45, 0.25)
            case .leanBulk: return (0.25, 0.55, 0.20)
            }
        }
    }

    /// WHOOP day-strain → suggested activity band, used to pre-suggest a choice the user still makes.
    ///
    /// Anchored on WHOOP's own published day-strain categories (0–9 light, 10–13 moderate,
    /// 14–17 strenuous, 18–21 all-out) so the mapping is theirs, not invented. The one judgement
    /// added here is splitting WHOOP's broad 0–9 "light" band at 6.0, because the book distinguishes
    /// "no exercise at all" from "1–3 hrs/week" and WHOOP does not.
    ///
    /// Advisory only: strain measures cardiovascular load, not hours, so it can never be more than a
    /// starting point for someone who knows their own week.
    static func suggestedActivity(avgDayStrain: Double) -> ActivityLevel {
        switch avgDayStrain {
        case ..<6: return .sedentary
        case ..<10: return .light
        case ..<14: return .moderate
        case ..<18: return .veryActive
        default: return .extraActive
        }
    }

    /// Inputs for one estimate. `weightKg` is the CURRENT weight — the latest reading Whoop holds,
    /// not an average. Averaging was tried and removed: two different weights appearing in the app
    /// is worse than a target that moves a little.
    struct Input {
        var sex: Sex
        var ageYears: Int
        var heightCm: Double
        var weightKg: Double
        var activity: ActivityLevel
        var goal: GoalDirection
    }

    /// The computed estimate. All goal fields rounded to whole numbers.
    struct Result: Equatable, Sendable {
        var bmr: Int
        var tdee: Int
        var calorieGoal: Int
        var proteinGoal: Int
        var fatGoal: Int
        var carbGoal: Int
        /// The inputs that produced this, persisted so the goal can re-derive itself weekly.
        var activity: ActivityLevel
        var goal: GoalDirection
    }

    /// BMR → TDEE → goal calories → macros. Pure and deterministic.
    static func estimate(_ input: Input) -> Result {
        let bmr = EnergyMath.computeBmr(.init(
            sex: input.sex,
            ageYears: input.ageYears,
            heightCm: input.heightCm,
            weightKg: input.weightKg
        ))
        let tdee = bmr * input.activity.factor
        let calorieGoal = max(0, tdee * input.goal.tdeeMultiplier)

        let split = input.goal.macroSplit
        let proteinGoal = calorieGoal * split.protein / kcalPerProteinG
        let carbGoal = calorieGoal * split.carb / kcalPerCarbG
        let fatGoal = calorieGoal * split.fat / kcalPerFatG

        return Result(
            bmr: Int(bmr.rounded()),
            tdee: Int(tdee.rounded()),
            calorieGoal: Int(calorieGoal.rounded()),
            proteinGoal: Int(proteinGoal.rounded()),
            fatGoal: Int(fatGoal.rounded()),
            carbGoal: Int(carbGoal.rounded()),
            activity: input.activity,
            goal: input.goal
        )
    }

    /// Convenience: build the input from a `Profile`.
    static func estimate(
        profile: Profile,
        activity: ActivityLevel,
        goal: GoalDirection
    ) -> Result {
        estimate(Input(
            sex: profile.sex,
            ageYears: profile.ageYears,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
            activity: activity,
            goal: goal
        ))
    }
}

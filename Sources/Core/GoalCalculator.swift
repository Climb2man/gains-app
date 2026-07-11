import Foundation

enum GoalCalculator {
    private static let kcalPerProteinG: Double = 4
    private static let kcalPerCarbG: Double = 4
    private static let kcalPerFatG: Double = 9

    private static let proteinGPerLb: Double = 0.8
    private static let fatGPerLb: Double = 0.35

    /// The five calculator.net activity multipliers, in order.
    enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
        case sedentary, light, moderate, active, veryActive

        var id: String { rawValue }

        /// The TDEE multiplier (BMR × factor). One source of truth for the factor.
        var factor: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .active: return 1.725
            case .veryActive: return 1.9
            }
        }

        /// The list label (matches calculator.net so the estimate is reproducible).
        var label: String {
            switch self {
            case .sedentary: return "Sedentary"
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .active: return "Active"
            case .veryActive: return "Very active"
            }
        }

        /// One-line gloss shown as the row subtitle; does not affect the math (which uses `factor`).
        var description: String {
            switch self {
            case .sedentary: return "Little or no exercise"
            case .light: return "Exercise 1–3 days/week"
            case .moderate: return "Exercise 3–5 days/week"
            case .active: return "Exercise 6–7 days/week"
            case .veryActive: return "Hard exercise / physical job"
            }
        }
    }

    /// Maintain = TDEE; lose/gain shift by a fixed daily kcal delta (½ lb/wk ≈ 250 kcal/day).
    /// Same options + ordering as calculator.net.
    enum GoalDirection: String, CaseIterable, Identifiable, Sendable {
        case lose2, lose1, lose0_5, maintain, gain0_5, gain1, gain2

        var id: String { rawValue }

        /// Daily kcal delta applied to maintenance (TDEE).
        var delta: Double {
            switch self {
            case .lose2: return -1000
            case .lose1: return -500
            case .lose0_5: return -250
            case .maintain: return 0
            case .gain0_5: return 250
            case .gain1: return 500
            case .gain2: return 1000
            }
        }

        var label: String {
            switch self {
            case .lose2: return "Lose 2 lb/week"
            case .lose1: return "Lose 1 lb/week"
            case .lose0_5: return "Lose 0.5 lb/week"
            case .maintain: return "Maintain weight"
            case .gain0_5: return "Gain 0.5 lb/week"
            case .gain1: return "Gain 1 lb/week"
            case .gain2: return "Gain 2 lb/week"
            }
        }
    }

    /// The inputs the calculator needs: metric for BMR plus
    /// `bodyWeightLb` for the per-pound macro split.
    struct Input {
        var sex: Sex
        var ageYears: Int
        var heightCm: Double
        var weightKg: Double
        var bodyWeightLb: Double
        var activity: ActivityLevel
        var goal: GoalDirection
    }

    /// The computed estimate. All values rounded to whole numbers for the goal fields.
    struct Result: Equatable, Sendable {
        var bmr: Int
        var tdee: Int
        var calorieGoal: Int
        var proteinGoal: Int
        var fatGoal: Int
        var carbGoal: Int
        /// The inputs that produced this estimate, persisted so the goal can re-derive itself
        /// from the current weight when it changes.
        var activity: ActivityLevel
        var goal: GoalDirection
    }

    /// Full calculator.net-style pass: BMR → TDEE → goal calories → macros. Pure + deterministic.
    static func estimate(_ input: Input) -> Result {
        let bmr = EnergyMath.computeBmr(.init(
            sex: input.sex,
            ageYears: input.ageYears,
            heightCm: input.heightCm,
            weightKg: input.weightKg
        ))
        let maintenance = bmr * input.activity.factor
        let calorieGoal = max(0, maintenance + input.goal.delta)

        // Protein and fat come from BODY WEIGHT and so are independent of `calorieGoal`, which means an
        // aggressive deficit on a light frame can make those two alone exceed the entire day: a 110 lb
        // sedentary profile losing 2 lb/week lands near 277 kcal against ~700 kcal of protein + fat.
        // Flooring carbs at 0 hid that, leaving a target set no one could satisfy. Scale protein and fat
        // by the SAME factor so they fit the calorie goal with the P:F ratio intact, and carbs settle at
        // 0 instead of being clamped from a negative. The calorie goal itself is left alone on purpose:
        // an aggressive target is flagged elsewhere, never overridden. `NutritionStore.autoAdjustGoals`
        // re-runs this on every weight change and persists it without review, so it must be coherent
        // on its own.
        let proteinFromWeight = input.bodyWeightLb * proteinGPerLb
        let fatFromWeight = input.bodyWeightLb * fatGPerLb
        let weightDerivedCals = proteinFromWeight * kcalPerProteinG + fatFromWeight * kcalPerFatG
        let fitToCalories = weightDerivedCals > calorieGoal && weightDerivedCals > 0
            ? calorieGoal / weightDerivedCals
            : 1
        let proteinGoal = proteinFromWeight * fitToCalories
        let fatGoal = fatFromWeight * fitToCalories
        let proteinCals = proteinGoal * kcalPerProteinG
        let fatCals = fatGoal * kcalPerFatG
        let carbGoal = max(0, (calorieGoal - proteinCals - fatCals) / kcalPerCarbG)

        return Result(
            bmr: Int(bmr.rounded()),
            tdee: Int(maintenance.rounded()),
            calorieGoal: Int(calorieGoal.rounded()),
            proteinGoal: Int(proteinGoal.rounded()),
            fatGoal: Int(fatGoal.rounded()),
            carbGoal: Int(carbGoal.rounded()),
            activity: input.activity,
            goal: input.goal
        )
    }

    /// Convenience: build the input from a `Profile` (bodyWeightLb derived from stored kg) plus
    /// the chosen activity and goal.
    static func estimate(profile: Profile, activity: ActivityLevel, goal: GoalDirection) -> Result {
        estimate(Input(
            sex: profile.sex,
            ageYears: profile.ageYears,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
            bodyWeightLb: Units.kgToLb(profile.weightKg),
            activity: activity,
            goal: goal
        ))
    }
}

import Foundation

enum EnergyMath {
    /// The metric inputs Mifflin–St Jeor needs, so callers needn't pass a full `Profile`.
    struct BmrInput {
        var sex: Sex
        var ageYears: Int
        var heightCm: Double
        var weightKg: Double
    }

    /// Resting BMR via Mifflin–St Jeor (kg/cm/years):
    ///   men:   10·kg + 6.25·cm − 5·age + 5
    ///   women: 10·kg + 6.25·cm − 5·age − 161
    /// `.other` averages the two sex constants (+5 and −161 → −78) to avoid assuming a sex.
    /// Returns raw (unrounded) kcal/day; callers round.
    static func computeBmr(_ input: BmrInput) -> Double {
        let base = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.ageYears)
        let sexConstant: Double
        switch input.sex {
        case .male: sexConstant = 5
        case .female: sexConstant = -161
        case .other: sexConstant = -78
        }
        return base + sexConstant
    }

    /// Convenience overload taking a full `Profile`.
    static func computeBmr(_ profile: Profile) -> Double {
        computeBmr(BmrInput(
            sex: profile.sex,
            ageYears: profile.ageYears,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg
        ))
    }
}

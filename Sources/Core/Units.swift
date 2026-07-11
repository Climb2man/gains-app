import Foundation

enum Units {
    private static let lbPerKg = 2.2046226
    private static let cmPerInch = 2.54
    private static let inchesPerFoot = 12

    /// Canonical kg → display pounds.
    static func kgToLb(_ kg: Double) -> Double {
        kg * lbPerKg
    }

    /// Input pounds → canonical kg (what we persist).
    static func lbToKg(_ lb: Double) -> Double {
        lb / lbPerKg
    }

    /// A stored kg value rendered as display pounds, one decimal, trailing ".0" dropped (e.g. "159.8").
    static func formatLb(_ kg: Double) -> String {
        Format.oneDecimal(kgToLb(kg))
    }

    /// ft/in input → canonical cm (what we persist from the imperial onboarding fields).
    static func ftInToCm(feet: Double, inches: Double) -> Double {
        (feet * Double(inchesPerFoot) + inches) * cmPerInch
    }

    /// Canonical cm → ft/in for pre-filling the imperial height fields from a stored heightCm.
    /// Rounds to the nearest inch, carrying 12in → +1ft (so 71.6in reads 6ft 0in, not 5ft 12in).
    static func cmToFtIn(_ cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / cmPerInch).rounded())
        let feet = totalInches / inchesPerFoot
        let inches = totalInches - feet * inchesPerFoot
        return (feet, inches)
    }
}

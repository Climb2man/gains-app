import Foundation

/// The user's sex, captured in onboarding.
enum Sex: String, Codable, Equatable, CaseIterable, Sendable {
    case female
    case male
    case other
}

/// The user profile.
///
/// `name` is optional (older profiles saved before the field existed still parse). Numeric ranges
/// (documented per field: ageYears 1…120, heightCm 50…260, weightKg 20…400) are enforced by a
/// later validation layer.
struct Profile: Codable, Equatable, Sendable {
    /// Optional display name (trimmed, 1…60 chars).
    var name: String?
    var sex: Sex
    /// Whole years, 1…120.
    var ageYears: Int
    /// Canonical metric height, 50…260 cm. Never rendered as cm. Convert to ft/in for display.
    var heightCm: Double
    /// Canonical metric weight, 20…400 kg. Never rendered as kg. Convert to lb for display.
    var weightKg: Double
    /// ISO 8601 timestamp string of when the profile was created.
    var createdAt: String
}

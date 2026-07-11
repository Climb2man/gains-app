import Foundation

struct WeightEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// Local calendar day, "YYYY-MM-DD".
    var date: String
    /// Canonical metric. Displayed in lb everywhere (Units.kgToLb).
    var kg: Double
    /// Optional body-fat %, when the user logs it.
    var bodyFatPct: Double?

    init(id: String = UUID().uuidString, date: String, kg: Double, bodyFatPct: Double? = nil) {
        self.id = id
        self.date = date
        self.kg = kg
        self.bodyFatPct = bodyFatPct
    }
}

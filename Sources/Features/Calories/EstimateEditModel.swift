import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EstimateEditModel {
    /// One editable line. Carries the original item so non-edited fields (id, citations, water flag,
    /// micronutrients) survive the round trip unchanged.
    struct Draft: Identifiable, Equatable {
        let id: String
        var name: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        fileprivate var original: LoggedFoodItem
    }

    private(set) var drafts: [Draft]

    init(items: [LoggedFoodItem]) {
        drafts = items.map { item in
            Draft(
                id: item.id,
                name: item.name,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                original: item
            )
        }
    }

    /// At least one line remains to log.
    var canConfirm: Bool { !drafts.isEmpty }

    /// Live total as the user edits (water excluded: captured items are never water).
    var totalCalories: Double {
        drafts.reduce(0) { $0 + max(0, $1.calories) }
    }

    /// A two-way binding into a specific draft, so each editor row edits in place.
    func binding(for draft: Draft) -> Binding<Draft> {
        Binding(
            get: { [weak self] in
                self?.drafts.first(where: { $0.id == draft.id }) ?? draft
            },
            set: { [weak self] newValue in
                guard let self, let index = drafts.firstIndex(where: { $0.id == newValue.id }) else { return }
                drafts[index] = newValue
            }
        )
    }

    func remove(_ id: String) {
        drafts.removeAll { $0.id == id }
    }

    /// Rebuild `LoggedFoodItem`s from the drafts. An edited line becomes the user's confirmed value
    /// (full confidence + note); an untouched line keeps its estimate metadata. Negative edits clamp to zero.
    func resolvedItems() -> [LoggedFoodItem] {
        drafts.map { draft in
            var item = draft.original
            let edited =
                draft.calories != draft.original.calories
                || draft.proteinG != draft.original.proteinG
                || draft.carbsG != draft.original.carbsG
                || draft.fatG != draft.original.fatG
            item.calories = max(0, draft.calories)
            item.proteinG = max(0, draft.proteinG)
            item.carbsG = max(0, draft.carbsG)
            item.fatG = max(0, draft.fatG)
            if edited {
                item.confidenceScore = 100
                let note = "Confirmed by you."
                item.assumptions = item.assumptions.map { "\($0) \(note)" } ?? note
            }
            return item
        }
    }
}

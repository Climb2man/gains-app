import Foundation
import Observation

@MainActor
@Observable
final class FoodLogSettingsStore {
    private static let biasKey = "@gains/foodlog/bias"
    private static let micronutrientsKey = "@gains/foodlog/micronutrients"

    /// The active calorie bias. Disclosed on every estimate.
    private(set) var bias: CalorieBias = .balanced
    /// Which micronutrients the totals bar + estimates include.
    private(set) var micronutrients: MicronutrientToggles = .off

    private let store: any KeyValueStore

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        load()
    }

    private func load() {
        if let stored = store.value(CalorieBias.self, forKey: Self.biasKey) { bias = stored }
        if let stored = store.value(MicronutrientToggles.self, forKey: Self.micronutrientsKey) {
            micronutrients = stored
        }
    }

    /// Override the bias. Persists.
    func setBias(_ next: CalorieBias) {
        bias = next
        store.setValue(next, forKey: Self.biasKey)
    }

    /// Derive the default bias from the onboarding goal without clobbering a prior user override:
    /// only writes when nothing has been set yet. Call once at onboarding completion.
    func applyDefaultBias(forGoalType goalType: String) {
        guard store.data(forKey: Self.biasKey) == nil else { return }
        setBias(CalorieBias.default(for: goalType))
    }

    /// Toggle the micronutrient set. Persists.
    func setMicronutrients(_ next: MicronutrientToggles) {
        micronutrients = next
        store.setValue(next, forKey: Self.micronutrientsKey)
    }
}

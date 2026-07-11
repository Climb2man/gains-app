import XCTest
@testable import Gains

@MainActor
final class JournalMirrorTests: XCTestCase {

    /// Stub pipeline, these tests log pre-resolved lines only, so the service must never be reached.
    private struct StubFoodService: FoodLoggingService {
        func resolveLine(_ request: FoodLineRequest) async throws -> FoodLineResult {
            FoodLineResult(items: [])
        }
        func resolveEdit(_ request: FoodEditRequest) async throws -> FoodLineResult {
            FoodLineResult(items: [])
        }
    }

    /// An isolated, wiped UserDefaults suite per test so persisted state never leaks across runs.
    private func isolatedStore(_ name: String) -> UserDefaultsStore {
        let suiteName = "gains.test.journal-mirror.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return UserDefaultsStore(defaults: suite)
    }

    private func foodItem(_ name: String, calories: Double, protein: Double = 0) -> LoggedFoodItem {
        LoggedFoodItem(name: name, calories: calories, proteinG: protein, carbsG: 0, fatG: 0,
                       citations: [], confidenceScore: 80)
    }

    private func waterItem(ml: Double) -> LoggedFoodItem {
        LoggedFoodItem(name: "\(Int(ml)) ml water", calories: 0, citations: [],
                       confidenceScore: 100, isWaterEntry: true, waterMilliliters: ml)
    }

    func testMappingSkipsWaterAndStampsDeterministicIds() {
        let food = foodItem("Salmon bowl", calories: 650, protein: 46)
        let line = FoodJournalEntry(
            foodText: "salmon bowl and water",
            items: [food, waterItem(ml: 473)],
            status: .resolved,
            loggedAt: "2026-06-09T12:00:00.000Z"
        )

        let rows = NutritionStore.entriesFromJournal([line])

        XCTAssertEqual(rows.count, 1, "water items must never become calorie rows")
        XCTAssertEqual(rows[0].id, "\(line.id)#\(food.id)", "ids must be deterministic so re-mirrors converge")
        XCTAssertEqual(rows[0].name, "Salmon bowl")
        XCTAssertEqual(rows[0].calories, 650)
        XCTAssertEqual(rows[0].proteinG, 46)
        XCTAssertEqual(rows[0].loggedAt, line.loggedAt, "rows inherit the LINE's timestamp")
    }

    func testPendingLineWithoutItemsContributesNothing() {
        let pending = FoodJournalEntry(foodText: "typing…", status: .pending,
                                       loggedAt: "2026-06-09T12:00:00.000Z")
        XCTAssertTrue(NutritionStore.entriesFromJournal([pending]).isEmpty)
    }

    func testMirrorReplacesStaleEntriesWholesale() {
        let nutrition = NutritionStore(store: isolatedStore("wholesale"))
        nutrition.addEntry(FoodInput(name: "stale seed", calories: 999, proteinG: 0,
                                     carbsG: 0, fatG: 0, source: .manual))

        let line = FoodJournalEntry(foodText: "lunch", items: [foodItem("Lunch", calories: 700)],
                                    status: .resolved, loggedAt: NutritionStore.isoNow())
        nutrition.mirrorJournal([line])

        XCTAssertEqual(nutrition.entries.map(\.name), ["Lunch"], "mirror replaces, never appends")

        nutrition.mirrorJournal([])
        XCTAssertTrue(nutrition.entries.isEmpty, "deleting the last journal line empties the rollup")
    }

    func testJournalMutationsDriveTheRollup() {
        let foodLog = FoodLogStore(service: StubFoodService(), store: isolatedStore("loop-journal"))
        let nutrition = NutritionStore(store: isolatedStore("loop-rollup"))
        foodLog.entriesDidChange = { nutrition.mirrorJournal($0) }
        nutrition.mirrorJournal(foodLog.entries)

        let lineID = foodLog.logCapturedLine(text: "salmon bowl",
                                             items: [foodItem("Salmon bowl", calories: 650, protein: 46),
                                                     waterItem(ml: 473)])
        XCTAssertEqual(nutrition.todayTotals.calories, 650)
        XCTAssertEqual(nutrition.todayTotals.proteinG, 46)

        let logged = foodLog.entries.first { $0.id == lineID }!
        var corrected = logged.items.first { !$0.isWaterEntry }!
        corrected.calories = 500
        foodLog.updateItem(entryID: lineID, item: corrected)
        XCTAssertEqual(nutrition.todayTotals.calories, 500)

        foodLog.removeLine(id: lineID)
        XCTAssertEqual(nutrition.todayTotals.calories, 0)
        XCTAssertTrue(nutrition.entries.isEmpty)
    }
}

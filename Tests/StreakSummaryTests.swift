import XCTest
@testable import Gains

@MainActor
final class StreakSummaryTests: XCTestCase {

    private let goals = Goals(calorieGoal: 2000, proteinGoal: 150, fatGoal: 70, carbGoal: 200, stepsGoal: 10000)

    /// A logged day N days before today. A "hit" day stays under the calorie goal AND meets protein.
    private func entry(daysAgo: Int, hit: Bool) -> FoodEntry {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        let noonLocal = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let iso = ISO8601DateFormatter().string(from: noonLocal)
        return FoodEntry(id: UUID().uuidString, name: "meal", calories: 1800,
                         proteinG: hit ? 160 : 100, carbsG: 0, fatG: 0,
                         source: .manual, loggedAt: iso)
    }

    func testNoEntriesIsZeroZero() {
        let r = NutritionStore.streakSummary(entries: [], goals: goals)
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.longest, 0)
    }

    func testThreeConsecutiveHitDays() {
        let entries = [0, 1, 2].map { entry(daysAgo: $0, hit: true) }
        let r = NutritionStore.streakSummary(entries: entries, goals: goals)
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.longest, 3)
    }

    func testTodayNotYetLoggedDoesNotZeroALiveStreak() {
        let entries = [1, 2].map { entry(daysAgo: $0, hit: true) }
        let r = NutritionStore.streakSummary(entries: entries, goals: goals)
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.longest, 2)
    }

    func testAGapBreaksCurrentButLongestCapturesTheLongerRun() {
        var entries = [0, 1].map { entry(daysAgo: $0, hit: true) }
        entries.append(entry(daysAgo: 2, hit: false))
        entries += [3, 4, 5].map { entry(daysAgo: $0, hit: true) }
        let r = NutritionStore.streakSummary(entries: entries, goals: goals)
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.longest, 3)
    }
}

import SwiftUI

/// Turns a day's real behaviour into a single 0–100 "momentum" score, then
/// tracks it over time as levels and streaks. Gamification done honestly: it
/// rewards planning, doing, focusing, habits, and reflecting — the actual
/// components of a good day — not vanity metrics.
enum MomentumEngine {

    struct Input {
        var plannedBlocks: Int
        var didMorningPlan: Bool
        var tasksCompletedToday: Int
        var focusMinutesToday: Int
        var habitsDue: Int
        var habitsDone: Int
        var journaledEvening: Bool
        var frogEaten: Bool
    }

    struct Breakdown: Identifiable {
        let id = UUID()
        var label: String
        var earned: Int
        var max: Int
        var icon: String
    }

    /// Component scores that sum to `score`.
    static func breakdown(_ input: Input) -> [Breakdown] {
        let plan = (input.plannedBlocks >= 3 || input.didMorningPlan) ? 20
            : min(20, input.plannedBlocks * 6)
        let done = min(20, input.tasksCompletedToday * 5)
        let focus = min(25, input.focusMinutesToday / 4)
        let habits = input.habitsDue > 0
            ? Int((Double(input.habitsDone) / Double(input.habitsDue)) * 20)
            : (input.habitsDone > 0 ? 20 : 10)
        let reflect = input.journaledEvening ? 10 : 0
        let frog = input.frogEaten ? 5 : 0
        return [
            Breakdown(label: "Planned", earned: plan, max: 20, icon: "wand.and.stars"),
            Breakdown(label: "Completed", earned: done, max: 20, icon: "checkmark.circle"),
            Breakdown(label: "Focused", earned: focus, max: 25, icon: "timer"),
            Breakdown(label: "Habits", earned: habits, max: 20, icon: "leaf"),
            Breakdown(label: "Reflected", earned: reflect, max: 10, icon: "book.closed"),
            Breakdown(label: "Ate the frog", earned: frog, max: 5, icon: "bolt.fill"),
        ]
    }

    static func score(_ input: Input) -> Int {
        min(100, breakdown(input).reduce(0) { $0 + $1.earned })
    }
}

/// Persists the daily momentum score so the app can show streaks, levels, and
/// a trend without recomputing history.
@MainActor
final class MomentumStore: ObservableObject {
    static let shared = MomentumStore()

    /// dayKey → score (0–100).
    @Published private(set) var history: [String: Int] = [:]

    private static let key = "chronos.momentum.v1"
    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            history = decoded
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Record today's score. Momentum only ever ratchets up within a day, so a
    /// morning glance doesn't lock in a low number.
    func record(_ score: Int, on day: Date = Date()) {
        let key = Fmt.dayKey(day)
        if score > (history[key] ?? 0) {
            history[key] = score
            save()
        }
    }

    func score(on day: Date) -> Int { history[Fmt.dayKey(day)] ?? 0 }

    /// Consecutive days (ending today) with a solid score. Today not-yet-solid
    /// doesn't break it.
    func streak(threshold: Int = 45, now: Date = Date()) -> Int {
        var count = 0
        var cursor = now.startOfDay
        if score(on: cursor) < threshold { cursor = cursor.adding(days: -1) }
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            if score(on: cursor) >= threshold { count += 1 } else { break }
            cursor = cursor.adding(days: -1)
        }
        return count
    }

    /// Trailing `days` scores oldest→newest for a sparkline.
    func trend(days: Int, now: Date = Date()) -> [Int] {
        (0..<days).reversed().map { score(on: now.adding(days: -$0)) }
    }

    var totalPoints: Int { history.values.reduce(0, +) }
    var level: Int { 1 + totalPoints / 500 }
    var pointsIntoLevel: Int { totalPoints % 500 }
    var progressToNextLevel: Double { Double(pointsIntoLevel) / 500 }

    var levelTitle: String {
        switch level {
        case 1: return "Getting Started"
        case 2: return "Finding Rhythm"
        case 3...4: return "In the Groove"
        case 5...7: return "Dialed In"
        case 8...11: return "On Fire"
        case 12...19: return "Unstoppable"
        default: return "Legendary"
        }
    }
}

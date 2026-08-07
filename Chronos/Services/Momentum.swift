import SwiftUI

/// Turns a day's real behaviour into a single 0–100 "momentum" score, then
/// tracks it over time as levels and streaks. Gamification done honestly: it
/// rewards planning, doing, focusing, habits, and reflecting — the actual
/// components of a good day — not vanity metrics.
enum MomentumEngine {

    struct Input {
        var plannedBlocks: Int
        var tasksCompletedToday: Int
        var focusMinutesToday: Int
        var habitsDue: Int
        var habitsDone: Int
        var frogEaten: Bool
    }

    /// Which part of a good day a component rewards — lets the UI route the
    /// "boost this" tip to the right action.
    enum Factor: String {
        case plan, complete, focus, habits, frog
    }

    struct Breakdown: Identifiable {
        let id = UUID()
        var factor: Factor
        var label: String
        var earned: Int
        var max: Int
        var icon: String
        /// Concrete, actionable advice for the points not yet earned ("" if maxed).
        var tip: String
        var remaining: Int { max - earned }
        var isComplete: Bool { earned >= max }
    }

    /// Component scores that sum to `score`, each with a plain-language tip for
    /// closing the gap.
    static func breakdown(_ input: Input) -> [Breakdown] {
        let plan = input.plannedBlocks >= 3 ? 25 : min(25, input.plannedBlocks * 8)
        let done = min(25, input.tasksCompletedToday * 5)
        let focus = min(30, input.focusMinutesToday / 4)
        let habits = input.habitsDue > 0
            ? Int((Double(input.habitsDone) / Double(input.habitsDue)) * 15)
            : (input.habitsDone > 0 ? 15 : 8)
        let frog = input.frogEaten ? 5 : 0

        let tasksToFull = Int(ceil(Double(25 - done) / 5.0))
        let minsToFull = (30 - focus) * 4
        let habitsLeft = max(0, input.habitsDue - input.habitsDone)

        return [
            Breakdown(factor: .plan, label: "Planned", earned: plan, max: 25, icon: "wand.and.stars",
                      tip: plan >= 25 ? "" : "Block out 3+ things for today (+\(25 - plan))"),
            Breakdown(factor: .complete, label: "Completed", earned: done, max: 25, icon: "checkmark.circle",
                      tip: done >= 25 ? "" : "Check off \(tasksToFull) more task\(tasksToFull == 1 ? "" : "s") today (+\(25 - done))"),
            Breakdown(factor: .focus, label: "Focused", earned: focus, max: 30, icon: "timer",
                      tip: focus >= 30 ? "" : "Run a focus session — \(minsToFull) more min for full credit (+\(30 - focus))"),
            Breakdown(factor: .habits, label: "Habits", earned: habits, max: 15, icon: "leaf",
                      tip: habits >= 15 ? "" : (habitsLeft > 0 ? "Finish \(habitsLeft) more due habit\(habitsLeft == 1 ? "" : "s") (+\(15 - habits))" : "Add a habit (+\(15 - habits))")),
            Breakdown(factor: .frog, label: "Ate the frog", earned: frog, max: 5, icon: "bolt.fill",
                      tip: frog >= 5 ? "" : "Finish your \u{201C}frog\u{201D} — the task you're avoiding (+5)"),
        ]
    }

    static func score(_ input: Input) -> Int {
        min(100, breakdown(input).reduce(0) { $0 + $1.earned })
    }

    /// Build today's momentum input from the live stores — one definition the
    /// card, the widget, and the app-wide gamification check all share.
    @MainActor
    static func dailyInput(service: EventKitService, life: LifeStore, focusLog: FocusLog,
                           hiddenCalendars: Set<String>, frogTaskID: String?,
                           day: Date = Date().startOfDay) -> Input {
        let blocks = service.blocks(on: day, hiddenCalendars: hiddenCalendars).filter { !$0.isAllDay }
        let habitsDue = life.activeHabits.filter { $0.isDue(on: day) }
        let frog = frogTaskID.flatMap { service.task(withID: $0) }
        return Input(
            plannedBlocks: blocks.count,
            tasksCompletedToday: service.tasks.filter { $0.isCompleted && ($0.completionDate?.isSameDay(as: day) ?? false) }.count,
            focusMinutesToday: focusLog.sessions(on: day).reduce(0) { $0 + $1.actualMinutes },
            habitsDue: habitsDue.count,
            habitsDone: habitsDue.filter { life.isDone($0, on: day) }.count,
            frogEaten: frog?.isCompleted ?? false
        )
    }

    /// The single highest-value thing left to do today (biggest point gain).
    static func nextBestAction(_ input: Input) -> Breakdown? {
        breakdown(input).filter { !$0.isComplete }.max { $0.remaining < $1.remaining }
    }
}

/// Persists the daily momentum score so the app can show streaks, levels, and
/// a trend without recomputing history.
@MainActor
final class MomentumStore: ObservableObject {
    static let shared = MomentumStore()

    /// dayKey → score (0–100).
    @Published private(set) var history: [String: Int] = [:]
    /// Bonus XP earned outside the daily score — completed challenges, etc.
    /// Counts toward your level alongside the daily momentum points.
    @Published private(set) var bonusXP: Int = 0

    private static let key = "chronos.momentum.v1"
    private static let bonusKey = "chronos.momentum.bonusxp.v1"
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
        bonusXP = UserDefaults.standard.integer(forKey: Self.bonusKey)
    }
    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Grant bonus XP (e.g. from a completed challenge). Ratchets your level.
    func addBonusXP(_ amount: Int) {
        guard amount > 0 else { return }
        bonusXP += amount
        UserDefaults.standard.set(bonusXP, forKey: Self.bonusKey)
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

    nonisolated static let solidThreshold = 45

    /// Streak-protecting "freezes" you earn as you go (one per 5 solid days),
    /// capped so they stay meaningful. A freeze bridges a single missed day so
    /// one off-day doesn't wipe weeks of momentum.
    var availableFreezes: Int {
        let solid = history.values.filter { $0 >= 70 }.count
        return min(2, solid / 5)
    }

    /// Consecutive days (ending today) with a solid score. Today not-yet-solid
    /// doesn't break it, and up to `availableFreezes` missed days are bridged.
    func streak(threshold: Int = solidThreshold, now: Date = Date()) -> Int {
        var freezesLeft = availableFreezes
        var count = 0
        var cursor = now.startOfDay
        if score(on: cursor) < threshold { cursor = cursor.adding(days: -1) }
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            if score(on: cursor) >= threshold {
                count += 1
            } else if count > 0 && freezesLeft > 0 {
                freezesLeft -= 1   // a freeze bridges this gap; streak survives
            } else {
                break
            }
            cursor = cursor.adding(days: -1)
        }
        return count
    }

    /// Longest run of solid days ever (no freezes — the honest record).
    func bestStreak(threshold: Int = solidThreshold) -> Int {
        guard let earliest = history.keys.compactMap(Fmt.day(fromKey:)).min() else { return 0 }
        var best = 0, run = 0
        var cursor = earliest.startOfDay
        let end = Date().startOfDay
        var guardCount = 0
        while cursor <= end && guardCount < 4000 {
            guardCount += 1
            if score(on: cursor) >= threshold { run += 1; best = max(best, run) } else { run = 0 }
            cursor = cursor.adding(days: 1)
        }
        return best
    }

    /// Number of days ever recorded at each tier.
    var activeDays: Int { history.values.filter { $0 > 0 }.count }
    var solidDays: Int { history.values.filter { $0 >= 70 }.count }
    var perfectDays: Int { history.values.filter { $0 >= 100 }.count }

    /// Trailing `days` scores oldest→newest for a sparkline.
    func trend(days: Int, now: Date = Date()) -> [Int] {
        (0..<days).reversed().map { score(on: now.adding(days: -$0)) }
    }

    /// A generic "consecutive days ending today where `predicate` is true"
    /// helper, so views can show focus/planning streaks from other stores.
    static func streak(endingToday predicate: (Date) -> Bool, now: Date = Date()) -> Int {
        var count = 0
        var cursor = now.startOfDay
        if !predicate(cursor) { cursor = cursor.adding(days: -1) }   // today grace
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            if predicate(cursor) { count += 1 } else { break }
            cursor = cursor.adding(days: -1)
        }
        return count
    }

    var totalPoints: Int { history.values.reduce(0, +) + bonusXP }
    var level: Int { 1 + totalPoints / 500 }
    var pointsIntoLevel: Int { totalPoints % 500 }
    var progressToNextLevel: Double { Double(pointsIntoLevel) / 500 }

    var levelTitle: String { Self.levelTitle(for: level) }

    nonisolated static func levelTitle(for level: Int) -> String {
        switch level {
        case ...1: return "Getting Started"
        case 2: return "Finding Rhythm"
        case 3...4: return "In the Groove"
        case 5...7: return "Dialed In"
        case 8...11: return "On Fire"
        case 12...19: return "Unstoppable"
        default: return "Legendary"
        }
    }
}

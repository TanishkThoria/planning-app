import Foundation

/// What a challenge measures. Each maps to a value we can read from the live
/// stores for a day or a week.
enum ChallengeMetric: String, Codable {
    case focusMinutes, tasks, momentum, habits, blocks, focusSessions, deepMinutes, journal, perfectDays
}

enum ChallengePeriod: String, Codable { case daily, weekly }

/// A bite-sized, time-boxed goal that grants bonus XP when you clear it. Daily
/// and weekly challenges rotate deterministically so everyone on the same day
/// sees the same set, but progress is entirely personal and on-device.
struct Challenge: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let metric: ChallengeMetric
    let period: ChallengePeriod
    let target: Int
    let xp: Int
    let colorHex: UInt32
}

/// A snapshot of everything challenges score against, computed once from the
/// live stores and handed to the ChallengeStore.
struct ChallengeMetrics {
    var focusMinutesDay = 0, focusMinutesWeek = 0
    var tasksDay = 0, tasksWeek = 0
    var momentumToday = 0
    var habitsDoneDay = 0
    var blocksDay = 0, blocksWeek = 0
    var focusSessionsDay = 0, focusSessionsWeek = 0
    var deepMinutesWeek = 0
    var journaledToday = false
    var perfectDaysWeek = 0

    /// Build the live snapshot from the stores — one source for the check and
    /// every challenge view.
    @MainActor
    static func live(service: EventKitService, life: LifeStore, focusLog: FocusLog,
                     hiddenCalendars: Set<String>, day: Date = Date().startOfDay) -> ChallengeMetrics {
        let momentum = MomentumStore.shared
        let weekDays = (0..<7).map { day.startOfWeek.adding(days: $0) }
        let stats = StatsEngine.compute(
            days: weekDays,
            blocks: { service.blocks(on: $0, hiddenCalendars: hiddenCalendars) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
        )
        let focusWeek = weekDays.reduce(0) { acc, d in acc + focusLog.sessions(on: d).reduce(0) { $0 + $1.actualMinutes } }
        let dueHabits = life.activeHabits.filter { $0.isDue(on: day) }
        return ChallengeMetrics(
            focusMinutesDay: focusLog.sessions(on: day).reduce(0) { $0 + $1.actualMinutes },
            focusMinutesWeek: focusWeek,
            tasksDay: service.tasks.filter { $0.isCompleted && ($0.completionDate?.isSameDay(as: day) ?? false) }.count,
            tasksWeek: stats.tasksCompleted,
            momentumToday: momentum.score(on: day),
            habitsDoneDay: dueHabits.filter { life.isDone($0, on: day) }.count,
            blocksDay: service.blocks(on: day, hiddenCalendars: hiddenCalendars).filter { !$0.isAllDay }.count,
            blocksWeek: stats.blockCount,
            focusSessionsDay: focusLog.sessions(on: day).count,
            focusSessionsWeek: stats.focusSessions,
            deepMinutesWeek: stats.deepMinutes,
            journaledToday: life.entry(for: day)?.hasEvening ?? false,
            perfectDaysWeek: weekDays.filter { momentum.score(on: $0) >= 100 }.count
        )
    }
}

@MainActor
final class ChallengeStore: ObservableObject {
    static let shared = ChallengeStore()

    /// "challengeID#periodKey" for challenges already cleared (XP granted).
    @Published private(set) var completed: Set<String> = []
    private var baselined = false

    private static let key = "chronos.challenges.completed.v1"
    private static let baselineKey = "chronos.challenges.baselined.v1"

    private init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
        baselined = UserDefaults.standard.bool(forKey: Self.baselineKey)
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.completed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(completed), forKey: Self.key)
        UserDefaults.standard.set(baselined, forKey: Self.baselineKey)
    }

    // MARK: Selection (deterministic per period)

    /// A stable string hash (Swift's `hashValue` is randomised per launch).
    private func stableHash(_ s: String) -> Int {
        var h = 5381
        for byte in s.utf8 { h = ((h << 5) &+ h) &+ Int(byte) }
        return abs(h)
    }

    private func pick(from pool: [Challenge], seed: Int, count: Int) -> [Challenge] {
        guard !pool.isEmpty else { return [] }
        let start = seed % pool.count
        return (0..<Swift.min(count, pool.count)).map { pool[(start + $0) % pool.count] }
    }

    func dailyChallenges(on day: Date = Date()) -> [Challenge] {
        pick(from: Self.dailyPool, seed: stableHash("day-" + Fmt.dayKey(day)), count: 3)
    }
    func weeklyChallenges(on day: Date = Date()) -> [Challenge] {
        pick(from: Self.weeklyPool, seed: stableHash("week-" + Fmt.dayKey(day.startOfWeek)), count: 3)
    }
    func activeChallenges(on day: Date = Date()) -> [Challenge] {
        dailyChallenges(on: day) + weeklyChallenges(on: day)
    }

    private func periodKey(_ c: Challenge, on day: Date) -> String {
        c.period == .daily ? Fmt.dayKey(day) : Fmt.dayKey(day.startOfWeek)
    }
    private func token(_ c: Challenge, on day: Date) -> String { "\(c.id)#\(periodKey(c, on: day))" }

    // MARK: Progress

    func value(_ c: Challenge, _ m: ChallengeMetrics) -> Int {
        switch (c.metric, c.period) {
        case (.focusMinutes, .daily): return m.focusMinutesDay
        case (.focusMinutes, .weekly): return m.focusMinutesWeek
        case (.tasks, .daily): return m.tasksDay
        case (.tasks, .weekly): return m.tasksWeek
        case (.momentum, _): return m.momentumToday
        case (.habits, _): return m.habitsDoneDay
        case (.blocks, .daily): return m.blocksDay
        case (.blocks, .weekly): return m.blocksWeek
        case (.focusSessions, .daily): return m.focusSessionsDay
        case (.focusSessions, .weekly): return m.focusSessionsWeek
        case (.deepMinutes, _): return m.deepMinutesWeek
        case (.journal, _): return m.journaledToday ? 1 : 0
        case (.perfectDays, _): return m.perfectDaysWeek
        }
    }

    func progress(_ c: Challenge, _ m: ChallengeMetrics) -> Double {
        c.target <= 0 ? 1 : Swift.min(1, Double(value(c, m)) / Double(c.target))
    }
    func isComplete(_ c: Challenge, on day: Date = Date()) -> Bool {
        completed.contains(token(c, on: day))
    }

    // MARK: Completion check (awards XP + celebration)

    func check(_ m: ChallengeMetrics, on day: Date = Date()) {
        let active = activeChallenges(on: day)
        // First time we ever run: silently mark whatever's already met so we
        // don't dump a pile of celebrations for work done before challenges
        // existed. Only genuinely new completions celebrate.
        if !baselined {
            for c in active where value(c, m) >= c.target { completed.insert(token(c, on: day)) }
            baselined = true
            save()
            return
        }
        var changed = false
        for c in active where value(c, m) >= c.target {
            let t = token(c, on: day)
            guard !completed.contains(t) else { continue }
            completed.insert(t)
            MomentumStore.shared.addBonusXP(c.xp)
            AchievementStore.shared.enqueue(
                Celebration(challengeTitle: c.title, xp: c.xp, icon: c.icon, colorHex: c.colorHex)
            )
            changed = true
        }
        if changed { save() }
    }

    // MARK: Pools

    private static func c(_ id: String, _ title: String, _ detail: String, _ icon: String,
                          _ metric: ChallengeMetric, _ period: ChallengePeriod,
                          _ target: Int, _ xp: Int, _ colorHex: UInt32) -> Challenge {
        Challenge(id: id, title: title, detail: detail, icon: icon,
                  metric: metric, period: period, target: target, xp: xp, colorHex: colorHex)
    }

    static let dailyPool: [Challenge] = [
        c("d.focus60", "Focus Sprint", "Log 60 minutes on the focus timer today.", "timer", .focusMinutes, .daily, 60, 60, 0x2FBF71),
        c("d.focus120", "In the Zone", "Two solid hours of focus today.", "gauge.high", .focusMinutes, .daily, 120, 120, 0x2FBF71),
        c("d.tasks3", "Knock 'em Out", "Complete 3 tasks today.", "checkmark.circle", .tasks, .daily, 3, 50, 0x5B8DEF),
        c("d.tasks6", "Clear the Deck", "Complete 6 tasks today.", "checklist", .tasks, .daily, 6, 100, 0x5B8DEF),
        c("d.mom70", "Solid Day", "Reach 70 momentum today.", "chart.line.uptrend.xyaxis", .momentum, .daily, 70, 80, 0xF2C14E),
        c("d.mom100", "Flawless", "Hit a perfect 100 momentum today.", "star.circle.fill", .momentum, .daily, 100, 160, 0xF2C14E),
        c("d.habits2", "Habit Stacker", "Check off 2 habits today.", "leaf.fill", .habits, .daily, 2, 50, 0x5BD899),
        c("d.blocks4", "Blocked Out", "Plan 4 time blocks today.", "square.stack.3d.up", .blocks, .daily, 4, 40, 0x7C8CF8),
        c("d.sessions2", "Double Down", "Run 2 focus sessions today.", "repeat", .focusSessions, .daily, 2, 60, 0x2FA8BF),
        c("d.journal", "Reflect", "Do your evening reflection.", "book.closed.fill", .journal, .daily, 1, 40, 0xE07BE0),
    ]

    static let weeklyPool: [Challenge] = [
        c("w.focus300", "Five-Hour Focus", "Bank 5 hours of focus this week.", "timer", .focusMinutes, .weekly, 300, 220, 0x2FBF71),
        c("w.focus600", "Focus Marathon", "Ten hours of focus this week.", "flame.fill", .focusMinutes, .weekly, 600, 380, 0x2FBF71),
        c("w.tasks20", "Task Crusher", "Complete 20 tasks this week.", "checklist.checked", .tasks, .weekly, 20, 220, 0x5B8DEF),
        c("w.deep180", "Deep Worker", "3 hours of deep work this week.", "brain.head.profile", .deepMinutes, .weekly, 180, 260, 0x9B8CFF),
        c("w.sessions10", "Ten Rounds", "Run 10 focus sessions this week.", "repeat.circle.fill", .focusSessions, .weekly, 10, 220, 0x2FA8BF),
        c("w.blocks20", "Master Planner", "Plan 20 time blocks this week.", "square.stack.3d.up.fill", .blocks, .weekly, 20, 180, 0x7C8CF8),
        c("w.perfect2", "Back to Back", "Two perfect-momentum days this week.", "star.circle.fill", .perfectDays, .weekly, 2, 320, 0xF2C14E),
    ]
}

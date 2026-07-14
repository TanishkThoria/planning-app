import Foundation
import SwiftUI

// MARK: - Shared palette

/// Named color choices for goals, habits, and tags. Stored as hex so they
/// round-trip through JSON without any platform color extraction.
enum Palette {
    static let options: [UInt32] = [
        0x7C8CF8, 0x4FD1C5, 0xF2B95C, 0xF0719B,
        0xA3E06B, 0x5BD899, 0xFF6B6B, 0xAEB6C2,
    ]
    static func color(_ hex: UInt32) -> Color { Color(hex: hex) }
}

// MARK: - Goals

enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case time       // spend N hours/week (optionally on a calendar)
    case milestone  // finish by a date
    case habitLink  // built on a habit's consistency

    var id: String { rawValue }
    var label: String {
        switch self {
        case .time: return "Time"
        case .milestone: return "Milestone"
        case .habitLink: return "Habit"
        }
    }
    var icon: String {
        switch self {
        case .time: return "hourglass"
        case .milestone: return "flag.checkered"
        case .habitLink: return "repeat"
        }
    }
}

struct Goal: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var detail: String = ""
    var colorHex: UInt32 = Palette.options[0]
    var kind: GoalKind = .time
    var weeklyHoursTarget: Double = 5      // for .time
    var linkedCalendarID: String?          // for .time (nil = any calendar)
    var deadline: Date?                    // for .milestone
    var milestoneProgress: Double = 0      // 0…1 manual, for .milestone
    var linkedHabitID: UUID?               // for .habitLink
    var isArchived: Bool = false
    var createdEpoch: TimeInterval = 0

    var color: Color { Palette.color(colorHex) }
}

// MARK: - Habits

enum HabitCadence: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly target"
        }
    }
}

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var iconName: String = "checkmark.seal"
    var colorHex: UInt32 = Palette.options[1]
    var cadence: HabitCadence = .daily
    var weeklyTarget: Int = 5               // for .weekly
    var reminderMinutes: Int?              // time-of-day nudge
    var createdEpoch: TimeInterval = 0
    var isArchived: Bool = false

    var color: Color { Palette.color(colorHex) }

    /// Is the habit expected on this weekday? (1 = Sunday … 7 = Saturday)
    func isDue(on day: Date) -> Bool {
        switch cadence {
        case .daily, .weekly: return true
        case .weekdays:
            let wd = Calendar.current.component(.weekday, from: day)
            return (2...6).contains(wd)
        }
    }
}

// MARK: - Journal (daily intentions + reflection)

struct JournalEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var dayKey: String                     // yyyy-MM-dd
    var intentions: [String] = ["", "", ""]
    var mood: Int?                         // 1…5
    var energy: Int?                       // 1…5
    var wins: String = ""
    var improve: String = ""
    var gratitude: String = ""
    var notes: String = ""
    var updatedEpoch: TimeInterval = 0

    var hasMorning: Bool { intentions.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    var hasEvening: Bool {
        !wins.isEmpty || !improve.isEmpty || !gratitude.isEmpty || mood != nil || energy != nil
    }
}

// MARK: - Day templates

struct TemplateBlock: Codable, Hashable {
    var title: String
    var startMinutes: Int
    var durationMinutes: Int
    var calendarID: String?
}

struct DayTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var blocks: [TemplateBlock]
    var createdEpoch: TimeInterval = 0

    /// Portable (id- and calendar-free) payload for sharing.
    private struct Portable: Codable {
        var name: String
        var blocks: [TemplateBlock]
    }

    /// A compact, shareable code — paste it into another Chronos to import the
    /// same day shape.
    var shareCode: String? {
        let portable = Portable(name: name, blocks: blocks.map {
            TemplateBlock(title: $0.title, startMinutes: $0.startMinutes, durationMinutes: $0.durationMinutes, calendarID: nil)
        })
        guard let data = try? JSONEncoder().encode(portable) else { return nil }
        return "chronos-tpl:" + data.base64EncodedString()
    }

    static func fromShareCode(_ code: String) -> DayTemplate? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("chronos-tpl:"),
              let data = Data(base64Encoded: String(trimmed.dropFirst("chronos-tpl:".count))),
              let portable = try? JSONDecoder().decode(Portable.self, from: data),
              !portable.blocks.isEmpty
        else { return nil }
        return DayTemplate(name: portable.name, blocks: portable.blocks)
    }
}

// MARK: - Time budgets

struct TimeBudget: Codable, Identifiable, Hashable {
    var id = UUID()
    var calendarID: String
    var weeklyHoursTarget: Double
}

// MARK: - Persisted container

private struct LifeData: Codable {
    var goals: [Goal] = []
    var habits: [Habit] = []
    var habitCompletions: [String] = []    // "habitID#yyyy-MM-dd"
    var journal: [JournalEntry] = []
    var templates: [DayTemplate] = []
    var budgets: [TimeBudget] = []
    /// "habitID#yyyy-MM-dd" days preserved by a streak freeze. Optional so
    /// blobs written before freezes existed still decode.
    var habitFreezes: [String]? = nil
}

/// One local store for the whole lifestyle layer — goals, habits, journal,
/// templates, budgets. Persisted as a single JSON blob in UserDefaults; it
/// never leaves the device. EventKit remains the source of truth for
/// calendar/reminder data; this holds only what Apple's apps can't.
@MainActor
final class LifeStore: ObservableObject {
    private static let key = "chronos.lifeData"

    @Published var goals: [Goal] { didSet { save() } }
    @Published var habits: [Habit] { didSet { save() } }
    @Published private(set) var habitCompletions: Set<String> { didSet { save() } }
    @Published private(set) var habitFreezes: Set<String> { didSet { save() } }
    @Published var journal: [JournalEntry] { didSet { save() } }
    @Published var templates: [DayTemplate] { didSet { save() } }
    @Published var budgets: [TimeBudget] { didSet { save() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LifeData.self, from: data) {
            goals = decoded.goals
            habits = decoded.habits
            habitCompletions = Set(decoded.habitCompletions)
            habitFreezes = Set(decoded.habitFreezes ?? [])
            journal = decoded.journal
            templates = decoded.templates
            budgets = decoded.budgets
        } else {
            goals = []
            habits = []
            habitCompletions = []
            habitFreezes = []
            journal = []
            templates = []
            budgets = []
        }
        observeCloudPulls()
    }

    /// Re-read from UserDefaults after iCloud sync writes a newer copy.
    func reloadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(LifeData.self, from: data) else { return }
        goals = decoded.goals
        habits = decoded.habits
        habitCompletions = Set(decoded.habitCompletions)
        habitFreezes = Set(decoded.habitFreezes ?? [])
        journal = decoded.journal
        templates = decoded.templates
        budgets = decoded.budgets
    }

    private func observeCloudPulls() {
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromDefaults() }
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }

    private var snapshot: LifeData {
        LifeData(
            goals: goals, habits: habits,
            habitCompletions: Array(habitCompletions),
            journal: journal, templates: templates, budgets: budgets,
            habitFreezes: Array(habitFreezes)
        )
    }

    // MARK: Backup / restore (portable JSON — goals, habits, journal, …)

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(snapshot))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    @discardableResult
    func importJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LifeData.self, from: data) else { return false }
        goals = decoded.goals
        habits = decoded.habits
        habitCompletions = Set(decoded.habitCompletions)
        journal = decoded.journal
        templates = decoded.templates
        budgets = decoded.budgets
        habitFreezes = Set(decoded.habitFreezes ?? [])
        return true
    }

    // MARK: Goals

    var activeGoals: [Goal] { goals.filter { !$0.isArchived } }

    func upsert(_ goal: Goal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) { goals[idx] = goal }
        else { var g = goal; g.createdEpoch = Date().timeIntervalSince1970; goals.append(g) }
    }
    func deleteGoal(_ id: UUID) { goals.removeAll { $0.id == id } }

    // MARK: Habits

    var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    func upsert(_ habit: Habit) {
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) { habits[idx] = habit }
        else { var h = habit; h.createdEpoch = Date().timeIntervalSince1970; habits.append(h) }
    }
    func deleteHabit(_ id: UUID) {
        habits.removeAll { $0.id == id }
        habitCompletions = habitCompletions.filter { !$0.hasPrefix("\(id)#") }
    }

    private func completionToken(_ habitID: UUID, _ day: Date) -> String {
        "\(habitID)#\(Fmt.dayKey(day))"
    }

    func isDone(_ habit: Habit, on day: Date) -> Bool {
        habitCompletions.contains(completionToken(habit.id, day))
    }

    func toggle(_ habit: Habit, on day: Date) {
        let token = completionToken(habit.id, day)
        if habitCompletions.contains(token) { habitCompletions.remove(token) }
        else { habitCompletions.insert(token) }
    }

    // MARK: Streak freezes (2 per habit per calendar month)

    func isFrozen(_ habit: Habit, on day: Date) -> Bool {
        habitFreezes.contains(completionToken(habit.id, day))
    }

    /// Freezes used by this habit in `day`'s calendar month.
    func freezesUsed(_ habit: Habit, inMonthOf day: Date = Date()) -> Int {
        let monthPrefix = "\(habit.id)#" + String(Fmt.dayKey(day).prefix(7))
        return habitFreezes.filter { $0.hasPrefix(monthPrefix) }.count
    }

    func canFreeze(_ habit: Habit, on day: Date) -> Bool {
        habit.isDue(on: day)
            && !isDone(habit, on: day)
            && !isFrozen(habit, on: day)
            && freezesUsed(habit, inMonthOf: day) < 2
    }

    /// Preserve the streak across a missed day. Duolingo-style grace: life
    /// happens, and one bad day shouldn't erase three weeks of showing up.
    func freeze(_ habit: Habit, on day: Date) {
        guard canFreeze(habit, on: day) else { return }
        habitFreezes.insert(completionToken(habit.id, day))
    }

    func isCompleted(habitID: UUID, on day: Date) -> Bool {
        habitCompletions.contains("\(habitID)#\(Fmt.dayKey(day))")
    }

    /// Consecutive due-days ending today (grace: today not-yet-done doesn't
    /// break it) on which the habit was completed.
    func streak(_ habit: Habit, now: Date = Date()) -> Int {
        var streak = 0
        var cursor = now.startOfDay
        if habit.isDue(on: cursor) && !isDone(habit, on: cursor) {
            cursor = cursor.adding(days: -1)
        }
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            if habit.isDue(on: cursor) {
                if isDone(habit, on: cursor) || isFrozen(habit, on: cursor) { streak += 1 } else { break }
            }
            cursor = cursor.adding(days: -1)
        }
        return streak
    }

    /// Completions in the last `days` days (for the heatmap / weekly target).
    func completionCount(_ habit: Habit, inLast days: Int, now: Date = Date()) -> Int {
        (0..<days).reduce(0) { acc, offset in
            acc + (isDone(habit, on: now.adding(days: -offset)) ? 1 : 0)
        }
    }

    func doneToday(_ habit: Habit, now: Date = Date()) -> Bool { isDone(habit, on: now) }

    // MARK: Journal

    func entry(for day: Date) -> JournalEntry? {
        journal.first { $0.dayKey == Fmt.dayKey(day) }
    }

    func entryOrNew(for day: Date) -> JournalEntry {
        entry(for: day) ?? JournalEntry(dayKey: Fmt.dayKey(day))
    }

    func upsert(_ entry: JournalEntry) {
        var e = entry
        e.updatedEpoch = Date().timeIntervalSince1970
        if let idx = journal.firstIndex(where: { $0.dayKey == e.dayKey }) { journal[idx] = e }
        else { journal.append(e) }
    }

    var journalStreak: Int {
        var streak = 0
        var cursor = Date().startOfDay
        if entry(for: cursor)?.hasEvening != true { cursor = cursor.adding(days: -1) }
        var guardCount = 0
        while guardCount < 400, let e = entry(for: cursor), e.hasEvening {
            streak += 1
            cursor = cursor.adding(days: -1)
            guardCount += 1
        }
        return streak
    }

    // MARK: Templates

    func addTemplate(_ template: DayTemplate) {
        var t = template
        t.createdEpoch = Date().timeIntervalSince1970
        templates.append(t)
    }
    func deleteTemplate(_ id: UUID) { templates.removeAll { $0.id == id } }

    // MARK: Budgets

    func budget(for calendarID: String) -> TimeBudget? {
        budgets.first { $0.calendarID == calendarID }
    }
    func setBudget(calendarID: String, hours: Double) {
        if hours <= 0 { budgets.removeAll { $0.calendarID == calendarID }; return }
        if let idx = budgets.firstIndex(where: { $0.calendarID == calendarID }) {
            budgets[idx].weeklyHoursTarget = hours
        } else {
            budgets.append(TimeBudget(calendarID: calendarID, weeklyHoursTarget: hours))
        }
    }
}

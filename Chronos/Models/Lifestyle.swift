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
    /// When true (and a time is set), this habit happens *at* `reminderMinutes`
    /// rather than being a loose "sometime today" — it shows on the day timeline
    /// at that moment and the alert fires then, like an appointment with
    /// yourself. Optional/defaulted so older saved habits decode unchanged.
    var anchored: Bool = false
    /// How long the anchored occurrence lasts on the timeline (minutes).
    var durationMinutes: Int = 30

    var color: Color { Palette.color(colorHex) }

    /// A habit that occupies a real slot on the day (anchored + has a time).
    var isTimeAnchored: Bool { anchored && reminderMinutes != nil }

    /// The anchored occurrence's start on a given day, if it has one.
    func anchorStart(on day: Date) -> Date? {
        guard let reminderMinutes, anchored else { return nil }
        return day.at(minutes: reminderMinutes)
    }

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
    /// Evening completion is defined by the evening-only reflection fields.
    /// Mood/energy are deliberately excluded: the morning ritual also records
    /// them, so counting them here marked the evening done as soon as you did
    /// the morning.
    var hasEvening: Bool {
        [wins, improve, gratitude].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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

/// Legacy per-calendar budget. Kept only so old saved blobs still decode; the
/// live feature is now `CategoryBudget` (per activity category).
struct TimeBudget: Codable, Identifiable, Hashable {
    var id = UUID()
    var calendarID: String
    var weeklyHoursTarget: Double
}

/// A weekly hours target for a whole activity category (Work, Gym, Social, …),
/// so budgets track what you're *doing*, not which calendar it lives on.
struct CategoryBudget: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: ActivityCategory
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
    // Self-growth layer (see Growth.swift). All optional so older blobs decode.
    var projects: [Project]? = nil
    var growthItems: [GrowthItem]? = nil
    var selfTraits: [SelfTrait]? = nil
    var niceToHaves: [NiceToHave]? = nil
    var categoryBudgets: [CategoryBudget]? = nil
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
    @Published var projects: [Project] { didSet { save() } }
    @Published var growthItems: [GrowthItem] { didSet { save() } }
    @Published var selfTraits: [SelfTrait] { didSet { save() } }
    @Published var niceToHaves: [NiceToHave] { didSet { save() } }
    @Published var categoryBudgets: [CategoryBudget] { didSet { save() } }

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
            projects = decoded.projects ?? []
            growthItems = decoded.growthItems ?? []
            selfTraits = decoded.selfTraits ?? []
            niceToHaves = decoded.niceToHaves ?? []
            categoryBudgets = decoded.categoryBudgets ?? []
        } else {
            goals = []
            habits = []
            habitCompletions = []
            habitFreezes = []
            journal = []
            templates = []
            budgets = []
            projects = []
            growthItems = []
            selfTraits = []
            niceToHaves = []
            categoryBudgets = []
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
        projects = decoded.projects ?? []
        growthItems = decoded.growthItems ?? []
        selfTraits = decoded.selfTraits ?? []
        niceToHaves = decoded.niceToHaves ?? []
        categoryBudgets = decoded.categoryBudgets ?? []
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
            habitFreezes: Array(habitFreezes),
            projects: projects, growthItems: growthItems,
            selfTraits: selfTraits, niceToHaves: niceToHaves,
            categoryBudgets: categoryBudgets
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
        projects = decoded.projects ?? []
        growthItems = decoded.growthItems ?? []
        selfTraits = decoded.selfTraits ?? []
        niceToHaves = decoded.niceToHaves ?? []
        categoryBudgets = decoded.categoryBudgets ?? []
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

    // MARK: Budgets (per activity category)

    func budget(for category: ActivityCategory) -> CategoryBudget? {
        categoryBudgets.first { $0.category == category }
    }
    func setBudget(category: ActivityCategory, hours: Double) {
        if hours <= 0 { categoryBudgets.removeAll { $0.category == category }; return }
        if let idx = categoryBudgets.firstIndex(where: { $0.category == category }) {
            categoryBudgets[idx].weeklyHoursTarget = hours
        } else {
            categoryBudgets.append(CategoryBudget(category: category, weeklyHoursTarget: hours))
        }
    }
    /// Categories with a target set, in the enum's natural order.
    var budgetedCategories: [CategoryBudget] {
        categoryBudgets.sorted {
            (ActivityCategory.allCases.firstIndex(of: $0.category) ?? 0)
                < (ActivityCategory.allCases.firstIndex(of: $1.category) ?? 0)
        }
    }

    // MARK: Projects

    /// Active projects, most recently started first.
    var activeProjects: [Project] {
        projects.filter { !$0.isArchived }.sorted { $0.startEpoch > $1.startEpoch }
    }
    /// Projects gently asking for a check-in, per their cadence.
    var projectsNeedingUpdate: [Project] { activeProjects.filter(\.isUpdateDue) }

    func upsert(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            var p = project
            if p.startEpoch == 0 { p.startEpoch = Date().timeIntervalSince1970 }
            projects.append(p)
        }
    }
    func deleteProject(_ id: UUID) { projects.removeAll { $0.id == id } }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    /// Log a dated update, optionally stamping the current progress reading.
    func addUpdate(to projectID: UUID, text: String, stampProgress: Bool) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let snap = stampProgress ? projects[idx].progress : nil
        projects[idx].updates.append(
            ProjectUpdate(epoch: Date().timeIntervalSince1970, text: text, progress: snap)
        )
    }
    func deleteUpdate(_ updateID: UUID, from projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].updates.removeAll { $0.id == updateID }
    }

    func toggleMilestone(_ milestoneID: UUID, in projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }),
              let mIdx = projects[pIdx].milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
        projects[pIdx].milestones[mIdx].isDone.toggle()
        projects[pIdx].milestones[mIdx].doneEpoch =
            projects[pIdx].milestones[mIdx].isDone ? Date().timeIntervalSince1970 : nil
    }

    // MARK: Growth commitments (start / stop doing)

    var activeGrowthItems: [GrowthItem] { growthItems.filter { !$0.isArchived } }
    func commitments(_ direction: GrowthDirection) -> [GrowthItem] {
        activeGrowthItems.filter { $0.direction == direction }.sorted { $0.createdEpoch < $1.createdEpoch }
    }

    func upsert(_ item: GrowthItem) {
        if let idx = growthItems.firstIndex(where: { $0.id == item.id }) {
            growthItems[idx] = item
        } else {
            var g = item
            if g.createdEpoch == 0 { g.createdEpoch = Date().timeIntervalSince1970 }
            growthItems.append(g)
        }
    }
    func deleteGrowthItem(_ id: UUID) { growthItems.removeAll { $0.id == id } }

    // MARK: Self-mirror (like / dislike)

    var likes: [SelfTrait] {
        selfTraits.filter { !$0.isArchived && $0.side == .like }.sorted { $0.createdEpoch < $1.createdEpoch }
    }
    var dislikes: [SelfTrait] {
        selfTraits.filter { !$0.isArchived && $0.side == .dislike }.sorted { $0.createdEpoch < $1.createdEpoch }
    }
    /// How many dislikes you've turned around into likes — the panel's score.
    var improvedTraitCount: Int { selfTraits.filter { $0.wasImproved && $0.side == .like }.count }

    func addTrait(_ text: String, side: SelfTraitSide) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selfTraits.append(SelfTrait(text: trimmed, side: side, createdEpoch: Date().timeIntervalSince1970))
    }
    func updateTrait(_ trait: SelfTrait) {
        if let idx = selfTraits.firstIndex(where: { $0.id == trait.id }) { selfTraits[idx] = trait }
    }
    func deleteTrait(_ id: UUID) { selfTraits.removeAll { $0.id == id } }

    /// Move a disliked trait over to the like side — the satisfying core gesture.
    func moveTraitToLike(_ id: UUID) {
        guard let idx = selfTraits.firstIndex(where: { $0.id == id }) else { return }
        selfTraits[idx].side = .like
        selfTraits[idx].movedEpoch = Date().timeIntervalSince1970
    }

    // MARK: Nice-to-haves (rewards)

    var activeNiceToHaves: [NiceToHave] {
        niceToHaves.filter { !$0.isArchived }.sorted { $0.createdEpoch < $1.createdEpoch }
    }

    func upsert(_ item: NiceToHave) {
        if let idx = niceToHaves.firstIndex(where: { $0.id == item.id }) {
            niceToHaves[idx] = item
        } else {
            var n = item
            if n.createdEpoch == 0 { n.createdEpoch = Date().timeIntervalSince1970 }
            niceToHaves.append(n)
        }
    }
    func deleteNiceToHave(_ id: UUID) { niceToHaves.removeAll { $0.id == id } }
    func markEnjoyed(_ id: UUID) {
        guard let idx = niceToHaves.firstIndex(where: { $0.id == id }) else { return }
        niceToHaves[idx].lastEnjoyedEpoch = Date().timeIntervalSince1970
    }
}

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
    var templates: [DayTemplate] = []
    var budgets: [TimeBudget] = []
    /// "habitID#yyyy-MM-dd" days preserved by a streak freeze. Optional so
    /// blobs written before freezes existed still decode.
    var habitFreezes: [String]? = nil
    // Self-growth layer (see Growth.swift). All optional so older blobs decode.
    var projects: [Project]? = nil
    var categoryBudgets: [CategoryBudget]? = nil
    // Identity / growth-OS layer (see Identity.swift, GrowthOS.swift). Optional.
    // RPG / memory / onboarding layer (see GrowthRPG.swift). Optional.
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
    @Published var templates: [DayTemplate] { didSet { save() } }
    @Published var budgets: [TimeBudget] { didSet { save() } }
    @Published var projects: [Project] { didSet { save() } }
    @Published var categoryBudgets: [CategoryBudget] { didSet { save() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LifeData.self, from: data) {
            goals = decoded.goals
            habits = decoded.habits
            habitCompletions = Set(decoded.habitCompletions)
            habitFreezes = Set(decoded.habitFreezes ?? [])
            templates = decoded.templates
            budgets = decoded.budgets
            projects = decoded.projects ?? []
            categoryBudgets = decoded.categoryBudgets ?? []
        } else {
            goals = []
            habits = []
            habitCompletions = []
            habitFreezes = []
            templates = []
            budgets = []
            projects = []
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
        templates = decoded.templates
        budgets = decoded.budgets
        projects = decoded.projects ?? []
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
            templates: templates, budgets: budgets,
            habitFreezes: Array(habitFreezes),
            projects: projects,
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
        templates = decoded.templates
        budgets = decoded.budgets
        habitFreezes = Set(decoded.habitFreezes ?? [])
        projects = decoded.projects ?? []
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

    /// Edit an existing update's text and/or stamped progress in place.
    func editUpdate(_ update: ProjectUpdate, in projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }),
              let uIdx = projects[pIdx].updates.firstIndex(where: { $0.id == update.id }) else { return }
        var edited = update
        edited.editedEpoch = Date().timeIntervalSince1970
        projects[pIdx].updates[uIdx] = edited
    }

    // MARK: Project progress (manual stamp, independent of milestones)

    /// Stamp an explicit progress reading (0…1). Pass nil to clear it and fall
    /// back to the milestone-derived percentage.
    func setProgress(_ value: Double?, for projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].manualProgress = value.map { min(max($0, 0), 1) }
    }

    // MARK: Project time logging

    func logTime(to projectID: UUID, minutes: Int, note: String = "", on date: Date = Date()) {
        guard minutes > 0, let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var logs = projects[idx].timeLogs ?? []
        logs.append(ProjectTimeEntry(epoch: date.timeIntervalSince1970, minutes: minutes, note: note))
        projects[idx].timeLogs = logs
    }
    func updateTimeEntry(_ entry: ProjectTimeEntry, in projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }),
              var logs = projects[pIdx].timeLogs,
              let eIdx = logs.firstIndex(where: { $0.id == entry.id }) else { return }
        logs[eIdx] = entry
        projects[pIdx].timeLogs = logs
    }
    func deleteTimeEntry(_ id: UUID, from projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIdx].timeLogs?.removeAll { $0.id == id }
    }

    // MARK: Project weekly objectives

    /// Set (or replace) the objective for the week containing `day`.
    func setWeeklyGoal(_ text: String, forWeekOf day: Date = Date(), in projectID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let key = Project.weekKey(for: day)
        var goals = projects[idx].weeklyGoals ?? []
        if let gIdx = goals.firstIndex(where: { $0.weekKey == key }) {
            if trimmed.isEmpty { goals.remove(at: gIdx) }
            else { goals[gIdx].text = trimmed }
        } else if !trimmed.isEmpty {
            goals.append(ProjectWeeklyGoal(weekKey: key, text: trimmed,
                                           createdEpoch: Date().timeIntervalSince1970))
        }
        projects[idx].weeklyGoals = goals
    }
    func toggleWeeklyGoal(_ id: UUID, in projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }),
              var goals = projects[pIdx].weeklyGoals,
              let gIdx = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[gIdx].isDone.toggle()
        goals[gIdx].doneEpoch = goals[gIdx].isDone ? Date().timeIntervalSince1970 : nil
        projects[pIdx].weeklyGoals = goals
    }
    func deleteWeeklyGoal(_ id: UUID, from projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIdx].weeklyGoals?.removeAll { $0.id == id }
    }

    // MARK: Project links (goals / habits / tasks)

    func toggleLinkedGoal(_ goalID: UUID, in projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var ids = projects[idx].linkedGoalIDs ?? []
        if let i = ids.firstIndex(of: goalID) { ids.remove(at: i) } else { ids.append(goalID) }
        projects[idx].linkedGoalIDs = ids.isEmpty ? nil : ids
    }
    func toggleLinkedHabit(_ habitID: UUID, in projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var ids = projects[idx].linkedHabitIDs ?? []
        if let i = ids.firstIndex(of: habitID) { ids.remove(at: i) } else { ids.append(habitID) }
        projects[idx].linkedHabitIDs = ids.isEmpty ? nil : ids
    }
    func toggleLinkedTask(_ taskID: String, in projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var ids = projects[idx].linkedTaskIDs ?? []
        if let i = ids.firstIndex(of: taskID) { ids.remove(at: i) } else { ids.append(taskID) }
        projects[idx].linkedTaskIDs = ids.isEmpty ? nil : ids
    }
    /// Linked goals/habits resolved against the current stores (skips any that
    /// were since deleted), preserving link order.
    func linkedGoals(for project: Project) -> [Goal] {
        (project.linkedGoalIDs ?? []).compactMap { id in goals.first { $0.id == id && !$0.isArchived } }
    }
    func linkedHabits(for project: Project) -> [Habit] {
        (project.linkedHabitIDs ?? []).compactMap { id in habits.first { $0.id == id && !$0.isArchived } }
    }

}

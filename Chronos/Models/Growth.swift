import Foundation
import SwiftUI

// The self-growth layer: long-term projects, "start / stop doing" commitments,
// a like/dislike self-mirror, and "nice-to-have" rewards. All of it is owned by
// `LifeStore` (see Lifestyle.swift) and persisted in the same on-device blob, so
// it rides along with backup and (on Chronos+) iCloud sync for free. Every type
// here is Codable with defaulted properties so older saved blobs keep decoding.

// MARK: - Long-term projects

/// A checkpoint on the way to finishing a project. Ordered by position.
struct ProjectMilestone: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var isDone: Bool = false
    var doneEpoch: TimeInterval?
    var targetDate: Date?

    var doneDate: Date? { doneEpoch.map { Date(timeIntervalSince1970: $0) } }
}

/// A dated log entry on a project — the daily/weekly "here's where things are"
/// note, optionally stamped with a progress reading at that moment. Editable
/// after the fact so you can flesh out or correct the record.
struct ProjectUpdate: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0
    var text: String = ""
    var progress: Double?          // 0…1 snapshot when the note was written
    /// Set when the note was later edited, so the log can show "edited".
    var editedEpoch: TimeInterval?

    var date: Date { Date(timeIntervalSince1970: epoch) }
    var wasEdited: Bool { editedEpoch != nil }
}

/// A logged chunk of time spent on a project. Entered by feel — a quick tap or a
/// custom amount — and fully editable/deletable, so the time record is honest.
struct ProjectTimeEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0
    var minutes: Int = 0
    var note: String = ""

    var date: Date { Date(timeIntervalSince1970: epoch) }
    var hours: Double { Double(minutes) / 60 }
}

/// A short objective for a single calendar week. The heart of tracking a fuzzy,
/// open-ended project: when you don't yet know the finish line, you steer it one
/// week at a time — set this week's aim, tick it off, and keep a trail of what
/// each week was for.
struct ProjectWeeklyGoal: Codable, Identifiable, Hashable {
    var id = UUID()
    var weekKey: String = ""       // ISO "yyyy-Www"
    var text: String = ""
    var isDone: Bool = false
    var createdEpoch: TimeInterval = 0
    var doneEpoch: TimeInterval?

    var doneDate: Date? { doneEpoch.map { Date(timeIntervalSince1970: $0) } }
}

/// How often you mean to check in on a project. Drives the gentle "time for an
/// update" nudge — never a nag.
enum ProjectCadence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "No reminders"
        case .daily: return "Daily updates"
        case .weekly: return "Weekly updates"
        }
    }
    var short: String {
        switch self {
        case .none: return "As needed"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var detail: String = ""
    var emoji: String = "🎯"
    var colorHex: UInt32 = Palette.options[0]
    var startEpoch: TimeInterval = 0
    var targetDate: Date?
    var milestones: [ProjectMilestone] = []
    var updates: [ProjectUpdate] = []
    /// When set, this overrides the milestone-derived percentage — a progress
    /// reading you stamp yourself, independent of any checklist. You can set it
    /// even while using milestones, and clear it to fall back to the ratio.
    var manualProgress: Double?
    var updateCadence: ProjectCadence = .weekly
    var isArchived: Bool = false
    var isComplete: Bool = false

    // New long-term-tracking fields — all optional so older saved blobs decode.

    /// Logged time spent on the project (see `ProjectTimeEntry`).
    var timeLogs: [ProjectTimeEntry]? = nil
    /// Rolling week-by-week objectives for open-ended work.
    var weeklyGoals: [ProjectWeeklyGoal]? = nil
    /// Goals, habits and tasks pulled into this project's orbit.
    var linkedGoalIDs: [UUID]? = nil
    var linkedHabitIDs: [UUID]? = nil
    var linkedTaskIDs: [String]? = nil     // EventKit reminder identifiers
    /// An optional running time target, in hours, for effort-based projects.
    var targetHours: Double? = nil
    /// When a live work session is running, the epoch it was clocked in at.
    /// nil means the clock is stopped. Optional/defaulted so older blobs decode.
    var activeClockInEpoch: TimeInterval? = nil

    var color: Color { Palette.color(colorHex) }

    var doneMilestoneCount: Int { milestones.filter(\.isDone).count }

    // MARK: Time logged

    var timeEntries: [ProjectTimeEntry] { timeLogs ?? [] }
    var totalLoggedMinutes: Int { timeEntries.reduce(0) { $0 + $1.minutes } }
    var totalLoggedHours: Double { Double(totalLoggedMinutes) / 60 }

    /// Minutes logged within the calendar week containing `day`.
    func loggedMinutes(inWeekOf day: Date = Date()) -> Int {
        let key = Self.weekKey(for: day)
        return timeEntries.filter { Self.weekKey(for: $0.date) == key }.reduce(0) { $0 + $1.minutes }
    }

    /// Minutes logged within the calendar month containing `day`. No default —
    /// keeping `loggedMinutes()` (no args) unambiguously the weekly total.
    func loggedMinutes(inMonthOf day: Date) -> Int {
        let cal = Calendar.current
        return timeEntries
            .filter { cal.isDate($0.date, equalTo: day, toGranularity: .month) }
            .reduce(0) { $0 + $1.minutes }
    }

    // MARK: Clock

    /// Whether a live work session is currently running.
    var isClockedIn: Bool { activeClockInEpoch != nil }
    /// When the running session started, if any.
    var clockInDate: Date? { activeClockInEpoch.map { Date(timeIntervalSince1970: $0) } }
    /// Whole minutes elapsed on the running session as of `now`.
    func clockElapsedMinutes(now: Date = Date()) -> Int {
        guard let start = clockInDate else { return 0 }
        return max(0, Int(now.timeIntervalSince(start) / 60))
    }

    // MARK: Monthly rollup

    /// A calendar month of logged time, for the long-horizon work record.
    struct MonthlyLog: Identifiable, Hashable {
        let key: String       // "yyyy-MM"
        let date: Date        // first day of the month, for labels
        let minutes: Int
        let entryCount: Int
        var id: String { key }
    }

    /// Logged time grouped by calendar month, newest first — the "how much have
    /// I put into this over the last few months" record.
    var monthlyLogs: [MonthlyLog] {
        let cal = Calendar.current
        var buckets: [String: (date: Date, minutes: Int, count: Int)] = [:]
        for entry in timeEntries {
            let comps = cal.dateComponents([.year, .month], from: entry.date)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            let monthStart = cal.date(from: comps) ?? entry.date
            var bucket = buckets[key] ?? (monthStart, 0, 0)
            bucket.minutes += entry.minutes
            bucket.count += 1
            buckets[key] = bucket
        }
        return buckets
            .map { MonthlyLog(key: $0.key, date: $0.value.date, minutes: $0.value.minutes, entryCount: $0.value.count) }
            .sorted { $0.key > $1.key }
    }

    // MARK: Weekly objectives

    var weeklyObjectives: [ProjectWeeklyGoal] { weeklyGoals ?? [] }
    func weeklyGoal(forWeekOf day: Date = Date()) -> ProjectWeeklyGoal? {
        let key = Self.weekKey(for: day)
        return weeklyObjectives.first { $0.weekKey == key }
    }
    /// Past weekly objectives, newest first (excludes the current week).
    func pastWeeklyGoals(before day: Date = Date()) -> [ProjectWeeklyGoal] {
        let key = Self.weekKey(for: day)
        return weeklyObjectives.filter { $0.weekKey != key }.sorted { $0.weekKey > $1.weekKey }
    }

    /// Stable ISO week identifier ("2026-W30") for grouping logs & objectives.
    static func weekKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// The first day of the week a `weekKey` refers to, for display labels.
    static func date(fromWeekKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]),
              parts[1].hasPrefix("W"), let week = Int(parts[1].dropFirst()) else { return nil }
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = Calendar.current.firstWeekday
        return Calendar.current.date(from: comps)
    }

    /// Fraction of milestones completed (0 when there are none).
    var milestoneProgress: Double {
        guard !milestones.isEmpty else { return 0 }
        return Double(doneMilestoneCount) / Double(milestones.count)
    }

    /// The number shown in rings and bars, in priority order: complete → 1; a
    /// manual reading you stamped; the milestone ratio; or — for an effort-based
    /// project with an hours target and no milestones — the share of that target
    /// you've logged (so tracked focus time visibly moves the ring).
    var progress: Double {
        if isComplete { return 1 }
        if let manual = manualProgress { return min(max(manual, 0), 1) }
        if !milestones.isEmpty { return milestoneProgress }
        if let target = targetHours, target > 0 { return min(1, totalLoggedHours / target) }
        return 0
    }

    var latestUpdate: ProjectUpdate? {
        updates.max(by: { $0.epoch < $1.epoch })
    }

    var startDate: Date { Date(timeIntervalSince1970: startEpoch) }

    /// Whole days until the target date (negative = overdue), nil if none set.
    var daysUntilTarget: Int? {
        guard let targetDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date().startOfDay, to: targetDate.startOfDay).day
        return days
    }

    /// Whether it's been long enough since the last update to gently surface one,
    /// based on the chosen cadence.
    var isUpdateDue: Bool {
        guard !isComplete, !isArchived, updateCadence != .none else { return false }
        let last = latestUpdate?.date
        switch updateCadence {
        case .none: return false
        case .daily:
            guard let last else { return true }
            return !Calendar.current.isDateInToday(last)
        case .weekly:
            guard let last else { return true }
            return Date().timeIntervalSince(last) > 7 * 86_400
        }
    }
}

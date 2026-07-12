import SwiftUI

enum TaskPriority: Int, CaseIterable, Identifiable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Short badge shown in rows — Reminders-style exclamation marks.
    var badge: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    var color: Color {
        switch self {
        case .none: return Theme.textTertiary
        case .low: return Theme.textSecondary
        case .medium: return Theme.warning
        case .high: return Theme.danger
        }
    }

    /// EKReminder uses 0 (none) and 1–9 (1 = highest).
    static func from(ekPriority: Int) -> TaskPriority {
        switch ekPriority {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    /// Sort key: high first, none last.
    var sortRank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }
}

/// Cognitive load of a task. Deep work is steered into your focus window by
/// the scheduler; shallow work fills the remaining gaps.
enum TaskEnergy: String, CaseIterable, Identifiable {
    case none
    case deep
    case shallow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Any"
        case .deep: return "Deep"
        case .shallow: return "Shallow"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dotted"
        case .deep: return "brain.head.profile"
        case .shallow: return "wind"
        }
    }

    var color: Color {
        switch self {
        case .none: return Theme.textTertiary
        case .deep: return Theme.accentChoices[0].color
        case .shallow: return Theme.success
        }
    }
}

/// Immutable snapshot of an Apple Reminder.
struct TaskItem: Identifiable, Hashable {
    let id: String            // calendarItemIdentifier
    var title: String
    var notes: String?        // display notes, metadata tokens stripped
    var dueDate: Date?
    var dueHasTime: Bool
    var isCompleted: Bool
    var completionDate: Date?
    var priority: TaskPriority
    var listID: String
    var listName: String
    var color: Color
    var estimateMinutes: Int?
    /// Preferred length of a single work session; when the estimate exceeds
    /// this, the scheduler chunks the task across multiple sessions/days.
    var sessionMinutes: Int?
    var energy: TaskEnergy
    /// Set when this reminder is a Chronos subtask of another reminder.
    var parentID: String?

    var isSubtask: Bool { parentID != nil }

    /// How the task should be broken up: nil = single block; otherwise the
    /// per-session length (never larger than the estimate).
    var effectiveSessionMinutes: Int? {
        guard let session = sessionMinutes, let est = estimateMinutes, est > session else { return nil }
        return session
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return dueHasTime ? due < Date() : due.endOfDay < Date()
    }

    var isDueToday: Bool {
        guard let due = dueDate else { return false }
        return due.isToday
    }

    /// Eisenhower urgency: overdue or due within the next 48 hours.
    var isUrgent: Bool {
        guard let due = dueDate else { return false }
        return due < Date().adding(minutes: 48 * 60)
    }

    /// Eisenhower importance rides on the reminder's priority.
    var isImportant: Bool {
        priority == .high || priority == .medium
    }

    func dueLabel() -> String? {
        guard let due = dueDate else { return nil }
        let day = Fmt.relativeDay(due)
        return dueHasTime ? "\(day) \(Fmt.time.string(from: due))" : day
    }
}

struct TaskDraft {
    var title: String = ""
    var listID: String?
    var hasDue: Bool = false
    var due: Date = .now
    var hasTime: Bool = false
    var priority: TaskPriority = .none
    var estimateMinutes: Int?
    var sessionMinutes: Int?
    var energy: TaskEnergy = .none
    var notes: String = ""
    var isCompleted: Bool = false
    var parentID: String?
    var recurrence: RecurrenceOption = .none
    var originalRecurrence: RecurrenceOption = .none
}

struct TaskEditorContext: Identifiable {
    let id = UUID()
    var draft: TaskDraft
    var existingID: String?
}

/// Chronos stores per-task metadata inside the reminder's notes as trailing
/// tokens — `[est:45m]` estimate, `[chunk:90m]` preferred session length,
/// `[energy:deep]` load, and `[sub:<reminder-id>]` subtask link — so
/// everything round-trips through Apple Reminders and syncs across devices
/// for free. (EventKit doesn't expose the Reminders app's native subtasks,
/// so Chronos subtasks are ordinary reminders carrying a parent pointer.)
enum TaskMetadata {

    private static let estimatePattern = "\\[est:(\\d+)m\\]"
    private static let chunkPattern = "\\[chunk:(\\d+)m\\]"
    private static let energyPattern = "\\[energy:(deep|shallow)\\]"
    private static let parentPattern = "\\[sub:([^\\]]+)\\]"

    private static let allPatterns = [estimatePattern, chunkPattern, energyPattern, parentPattern]

    private static func firstGroup(_ pattern: String, in notes: String?) -> String? {
        guard let notes,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range(at: 1), in: notes)
        else { return nil }
        return String(notes[range])
    }

    static func estimate(from notes: String?) -> Int? {
        firstGroup(estimatePattern, in: notes).flatMap { Int($0) }
    }

    static func session(from notes: String?) -> Int? {
        firstGroup(chunkPattern, in: notes).flatMap { Int($0) }
    }

    static func energy(from notes: String?) -> TaskEnergy {
        firstGroup(energyPattern, in: notes).flatMap { TaskEnergy(rawValue: $0) } ?? .none
    }

    static func parentID(from notes: String?) -> String? {
        firstGroup(parentPattern, in: notes)
    }

    static func strippingTokens(_ notes: String?) -> String? {
        guard var text = notes else { return nil }
        for pattern in allPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Combines display notes + metadata back into the stored notes string.
    static func encode(
        notes: String,
        estimateMinutes: Int?,
        sessionMinutes: Int?,
        energy: TaskEnergy,
        parentID: String?
    ) -> String? {
        let base = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !base.isEmpty { parts.append(base) }
        var tokens: [String] = []
        if let est = estimateMinutes, est > 0 { tokens.append("[est:\(est)m]") }
        if let session = sessionMinutes, session > 0 { tokens.append("[chunk:\(session)m]") }
        if energy != .none { tokens.append("[energy:\(energy.rawValue)]") }
        if let parentID, !parentID.isEmpty { tokens.append("[sub:\(parentID)]") }
        if !tokens.isEmpty { parts.append(tokens.joined(separator: " ")) }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

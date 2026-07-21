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
/// note, optionally stamped with a progress reading at that moment.
struct ProjectUpdate: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0
    var text: String = ""
    var progress: Double?          // 0…1 snapshot when the note was written

    var date: Date { Date(timeIntervalSince1970: epoch) }
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
    /// When set, this overrides the milestone-derived percentage — for projects
    /// you'd rather track by feel than by checklist.
    var manualProgress: Double?
    var updateCadence: ProjectCadence = .weekly
    var isArchived: Bool = false
    var isComplete: Bool = false

    var color: Color { Palette.color(colorHex) }

    var doneMilestoneCount: Int { milestones.filter(\.isDone).count }

    /// Fraction of milestones completed (0 when there are none).
    var milestoneProgress: Double {
        guard !milestones.isEmpty else { return 0 }
        return Double(doneMilestoneCount) / Double(milestones.count)
    }

    /// The number shown in rings and bars: complete → 1, else the manual reading
    /// if you set one, otherwise the milestone ratio.
    var progress: Double {
        if isComplete { return 1 }
        if let manual = manualProgress { return min(max(manual, 0), 1) }
        return milestoneProgress
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

// MARK: - Start doing / Stop doing

/// The two directions of a self-improvement commitment.
enum GrowthDirection: String, Codable, CaseIterable, Identifiable {
    case start, stop
    var id: String { rawValue }
    var label: String { self == .start ? "Start doing" : "Stop doing" }
    var verb: String { self == .start ? "Start" : "Stop" }
    var icon: String { self == .start ? "plus.circle.fill" : "minus.circle.fill" }
    var colorHex: UInt32 { self == .start ? 0x5BD899 : 0xFF6B6B }
    var color: Color { Palette.color(colorHex) }
}

/// One ongoing commitment: a thing you want to start, or stop, doing.
struct GrowthItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String = ""
    var direction: GrowthDirection = .start
    var note: String = ""
    var createdEpoch: TimeInterval = 0
    var isArchived: Bool = false

    var createdDate: Date { Date(timeIntervalSince1970: createdEpoch) }
    /// Whole days you've held this commitment.
    var daysHeld: Int {
        max(0, Calendar.current.dateComponents([.day], from: createdDate.startOfDay, to: Date().startOfDay).day ?? 0)
    }
}

// MARK: - Self-mirror (things I like / dislike about myself)

enum SelfTraitSide: String, Codable, Hashable {
    case like, dislike
}

/// A single line in the self-mirror. A dislike can be "moved to the like side"
/// once you've turned it around — the small, satisfying core of the panel.
struct SelfTrait: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String = ""
    var side: SelfTraitSide = .like
    var createdEpoch: TimeInterval = 0
    /// Set when a dislike is moved over to the like side — powers the "you turned
    /// this around" celebration and the count of things you've improved.
    var movedEpoch: TimeInterval?
    var isArchived: Bool = false

    var wasImproved: Bool { movedEpoch != nil }
}

// MARK: - Nice-to-haves (downtime & rewards)

/// Something you'd enjoy doing *if there's time* — downtime, fun, a treat. The
/// carrot: clear your real work and you unlock room for these.
struct NiceToHave: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var emoji: String = "✨"
    var estimateMinutes: Int = 30
    var colorHex: UInt32 = Palette.options[4]
    var createdEpoch: TimeInterval = 0
    var lastEnjoyedEpoch: TimeInterval?
    var isArchived: Bool = false

    var color: Color { Palette.color(colorHex) }
    var lastEnjoyedDate: Date? { lastEnjoyedEpoch.map { Date(timeIntervalSince1970: $0) } }
}

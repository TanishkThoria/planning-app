import Foundation
import SwiftUI

// The Identity layer — the spine of Chronos 2.0's "become who you want to
// become" thesis. Everything here is Codable with defaulted properties so older
// saved blobs keep decoding, and it's owned by `LifeStore` (see Lifestyle.swift)
// so it rides backup + (on Chronos+) iCloud sync for free.
//
// The core idea: you don't become an identity through goals — you become it
// through *evidence*. A pillar ("Health", "Discipline") accrues evidence from the
// real things you already do (a completed habit, a focus session, a shipped
// milestone), and Chronos shows how much you're *becoming* that person — a
// measure of momentum, never a measure of worth.

// MARK: - Identity pillars

/// One facet of the person the user is becoming. Pillars are the buckets that
/// evidence flows into.
struct IdentityPillar: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var detail: String = ""
    var iconName: String = "sparkles"
    var colorHex: UInt32 = Palette.options[0]
    var createdEpoch: TimeInterval = 0
    var isArchived: Bool = false
    var sortIndex: Int = 0

    // What counts as evidence for this pillar. All optional so older blobs decode.
    /// Activity categories whose completed tasks / focus sessions count.
    var categories: [ActivityCategory]? = nil
    /// Habits, goals and projects explicitly aimed at this pillar.
    var linkedHabitIDs: [UUID]? = nil
    var linkedGoalIDs: [UUID]? = nil
    var linkedProjectIDs: [UUID]? = nil

    var color: Color { Palette.color(colorHex) }
    var categoryList: [ActivityCategory] { categories ?? [] }

    /// The eight suggested starting pillars. Users can keep, edit, or replace.
    static let presets: [IdentityPillar] = [
        .init(name: "Health", detail: "Strong, rested, energised", iconName: "heart.fill",
              colorHex: 0x5BD899, categories: [.fitness, .sports, .health, .meal, .rest]),
        .init(name: "Career", detail: "Skilled, focused, effective", iconName: "briefcase.fill",
              colorHex: 0x5B6CF0, categories: [.work]),
        .init(name: "Learning", detail: "Curious, always growing", iconName: "book.fill",
              colorHex: 0x4C9BFF, categories: [.school, .classes, .study]),
        .init(name: "Relationships", detail: "Present with people who matter", iconName: "person.2.fill",
              colorHex: 0xFF6B9D, categories: [.social]),
        .init(name: "Creativity", detail: "Making, not just consuming", iconName: "paintbrush.fill",
              colorHex: 0x9C7BFA, categories: [.creative]),
        .init(name: "Discipline", detail: "Doing it when it's hard", iconName: "flame.fill",
              colorHex: 0xFF7A59, categories: [.work, .study, .fitness]),
        .init(name: "Financial", detail: "Responsible, building freedom", iconName: "dollarsign.circle.fill",
              colorHex: 0x22C3C9, categories: [.errand, .chores]),
        .init(name: "Style", detail: "Presenting the person I'm becoming", iconName: "tshirt.fill",
              colorHex: 0xFFB23E, categories: [.errand]),
    ]
}

// MARK: - Evidence

/// Where a piece of identity evidence came from.
enum EvidenceSource: String, Codable, Hashable, CaseIterable {
    case habit, task, focus, milestone, journal, reflection, manual

    var label: String {
        switch self {
        case .habit: return "Habit"
        case .task: return "Task"
        case .focus: return "Focus"
        case .milestone: return "Milestone"
        case .journal: return "Journal"
        case .reflection: return "Reflection"
        case .manual: return "Noted"
        }
    }
    var icon: String {
        switch self {
        case .habit: return "repeat"
        case .task: return "checkmark.circle.fill"
        case .focus: return "timer"
        case .milestone: return "flag.checkered"
        case .journal: return "book.closed.fill"
        case .reflection: return "sparkles"
        case .manual: return "hand.point.up.left.fill"
        }
    }
}

/// A single proof-of-becoming. Auto-evidence (from habits/tasks/focus/milestones)
/// is computed live and never stored; only user-authored evidence (reflection,
/// manual) is persisted, tagged with its `pillarID`.
struct IdentityEvidence: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0
    var pillarID: UUID
    var source: EvidenceSource = .manual
    var text: String = ""
    /// 1 = a small proof, 2 = solid, 3 = a standout. Weights the becoming score.
    var strength: Int = 1

    var date: Date { Date(timeIntervalSince1970: epoch) }
}

// MARK: - Future Self & visions

/// The aspirational identity the whole app orients toward. One per user; stored
/// as a single optional value in `LifeData`.
struct FutureSelf: Codable, Hashable {
    var name: String = ""                 // "The disciplined engineer-athlete"
    var summary: String = ""              // one honest paragraph
    var attributes: [String] = []         // "Physically strong", "Calm", …
    var visionOneYear: String = ""
    var visionFiveYear: String = ""
    var visionTenYear: String = ""
    /// "What does this future person do *today*?" — the bridge back to now.
    var dailyActions: [String] = []
    var updatedEpoch: TimeInterval = 0

    var isDefined: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || !attributes.isEmpty
    }
}

/// The three vision horizons, used to label the Future Self timeline.
enum VisionHorizon: String, CaseIterable, Identifiable {
    case oneYear, fiveYear, tenYear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneYear: return "1 year"
        case .fiveYear: return "5 years"
        case .tenYear: return "10 years"
        }
    }
    var icon: String {
        switch self {
        case .oneYear: return "1.circle.fill"
        case .fiveYear: return "5.circle.fill"
        case .tenYear: return "10.circle.fill"
        }
    }
    var prompt: String {
        switch self {
        case .oneYear: return "A year from now, who have you become?"
        case .fiveYear: return "Five years out — the shape of your life."
        case .tenYear: return "Ten years — the person you're building toward."
        }
    }
}

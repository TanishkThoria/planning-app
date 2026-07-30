import Foundation
import SwiftUI

// The RPG / life-archive layer of Chronos: character attributes that level up
// from real evidence, a memory timeline of meaningful life events, the
// life-satisfaction radar captured at onboarding, and the identity archetypes a
// user picks. All Codable with defaulted properties (older blobs decode), all
// owned by `LifeStore`.

// MARK: - Character attributes

/// The six attributes of the person you're building. They rise only through
/// evidence — never a manual slider — so the character sheet stays honest.
enum Attribute: String, Codable, CaseIterable, Identifiable {
    case discipline, knowledge, fitness, creativity, relationships, organization
    var id: String { rawValue }

    var title: String {
        switch self {
        case .discipline: return "Discipline"
        case .knowledge: return "Knowledge"
        case .fitness: return "Fitness"
        case .creativity: return "Creativity"
        case .relationships: return "Relationships"
        case .organization: return "Organization"
        }
    }
    var icon: String {
        switch self {
        case .discipline: return "flame.fill"
        case .knowledge: return "book.fill"
        case .fitness: return "figure.run"
        case .creativity: return "paintbrush.pointed.fill"
        case .relationships: return "person.2.fill"
        case .organization: return "square.grid.2x2.fill"
        }
    }
    var colorHex: UInt32 {
        switch self {
        case .discipline: return 0xFF7A59
        case .knowledge: return 0x4C9BFF
        case .fitness: return 0x3FC97A
        case .creativity: return 0x9C7BFA
        case .relationships: return 0xFF6B9D
        case .organization: return 0x22C3C9
        }
    }
    var color: Color { Color(hex: colorHex) }

    /// Activity categories whose focus time & finished tasks feed this attribute.
    var categories: [ActivityCategory] {
        switch self {
        case .discipline: return [.work, .study, .chores]
        case .knowledge: return [.school, .classes, .study]
        case .fitness: return [.fitness, .sports, .health]
        case .creativity: return [.creative]
        case .relationships: return [.social]
        case .organization: return [.errand, .chores, .work]
        }
    }
    var blurb: String {
        switch self {
        case .discipline: return "Doing it when it's hard"
        case .knowledge: return "Always learning"
        case .fitness: return "Strong and rested"
        case .creativity: return "Making, not consuming"
        case .relationships: return "Present with people"
        case .organization: return "In control of your time"
        }
    }
}

// MARK: - Memory engine (life timeline)

/// The kind of moment — shapes its icon and how it's surfaced.
enum LifeEventKind: String, Codable, CaseIterable, Identifiable {
    case milestone, achievement, project, reflection, personal, start
    var id: String { rawValue }
    var label: String {
        switch self {
        case .milestone: return "Milestone"
        case .achievement: return "Achievement"
        case .project: return "Project"
        case .reflection: return "Reflection"
        case .personal: return "Personal"
        case .start: return "Beginning"
        }
    }
    var icon: String {
        switch self {
        case .milestone: return "flag.checkered"
        case .achievement: return "trophy.fill"
        case .project: return "square.stack.3d.up.fill"
        case .reflection: return "sparkles"
        case .personal: return "heart.fill"
        case .start: return "flag.fill"
        }
    }
    var colorHex: UInt32 {
        switch self {
        case .milestone: return 0x5B6CF0
        case .achievement: return 0xFFB23E
        case .project: return 0x9C7BFA
        case .reflection: return 0x22C3C9
        case .personal: return 0xFF6B9D
        case .start: return 0x3FC97A
        }
    }
    var color: Color { Color(hex: colorHex) }
}

/// A meaningful moment on the user's life timeline — "accepted into college",
/// "finished the thesis", "first 10k". Chronos slowly becomes a life archive.
struct LifeEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0            // when it happened
    var title: String = ""
    var note: String = ""
    var kind: LifeEventKind = .milestone
    var emoji: String = ""
    var createdEpoch: TimeInterval = 0     // when it was recorded
    /// Auto-captured events (project done, level-up) carry a dedupe key so they
    /// aren't recorded twice; user events leave it nil.
    var autoKey: String?

    var date: Date { Date(timeIntervalSince1970: epoch) }
    var displayIcon: String { emoji.isEmpty ? kind.icon : emoji }
}

// MARK: - Life-satisfaction radar (onboarding + periodic check-ins)

/// The ten life dimensions rated at onboarding and revisited over time — the
/// radar chart that makes "where am I now" concrete.
enum LifeArea: String, Codable, CaseIterable, Identifiable {
    case health, fitness, discipline, organization, stress, sleep, learning, social, money, purpose
    var id: String { rawValue }
    var title: String {
        switch self {
        case .health: return "Health"
        case .fitness: return "Fitness"
        case .discipline: return "Discipline"
        case .organization: return "Organization"
        case .stress: return "Calm"
        case .sleep: return "Sleep"
        case .learning: return "Learning"
        case .social: return "Social"
        case .money: return "Money"
        case .purpose: return "Purpose"
        }
    }
    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .fitness: return "figure.run"
        case .discipline: return "flame.fill"
        case .organization: return "square.grid.2x2.fill"
        case .stress: return "wind"
        case .sleep: return "moon.fill"
        case .learning: return "book.fill"
        case .social: return "person.2.fill"
        case .money: return "dollarsign.circle.fill"
        case .purpose: return "star.fill"
        }
    }
}

/// One dated snapshot of the satisfaction radar (0…10 per area).
struct SatisfactionSnapshot: Codable, Identifiable, Hashable {
    var id = UUID()
    var epoch: TimeInterval = 0
    var ratings: [String: Int] = [:]       // LifeArea.rawValue → 0…10

    var date: Date { Date(timeIntervalSince1970: epoch) }
    func rating(_ area: LifeArea) -> Int { ratings[area.rawValue] ?? 5 }
    var average: Double {
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.values.reduce(0, +)) / Double(ratings.count)
    }
}

// MARK: - Identity archetypes (onboarding stage 1)

/// A starting identity the user picks in onboarding. Each seeds a matching set of
/// pillars and hints at the habits and attributes it emphasises.
struct IdentityArchetype: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let colorHex: UInt32
    /// Names of pillars (from IdentityPillar.presets) this archetype emphasises.
    let pillars: [String]
    var color: Color { Color(hex: colorHex) }

    static let all: [IdentityArchetype] = [
        .init(id: "student", title: "Elite Student", icon: "graduationcap.fill", colorHex: 0x4C9BFF,
              pillars: ["Learning", "Discipline"]),
        .init(id: "athlete", title: "Athlete", icon: "figure.run", colorHex: 0x3FC97A,
              pillars: ["Health", "Discipline"]),
        .init(id: "entrepreneur", title: "Entrepreneur", icon: "briefcase.fill", colorHex: 0x5B6CF0,
              pillars: ["Career", "Discipline", "Financial"]),
        .init(id: "creative", title: "Creative", icon: "paintbrush.pointed.fill", colorHex: 0x9C7BFA,
              pillars: ["Creativity"]),
        .init(id: "reader", title: "Reader", icon: "book.fill", colorHex: 0x22C3C9,
              pillars: ["Learning"]),
        .init(id: "social", title: "Connector", icon: "person.2.fill", colorHex: 0xFF6B9D,
              pillars: ["Relationships"]),
        .init(id: "health", title: "Health-Focused", icon: "heart.fill", colorHex: 0x5BD899,
              pillars: ["Health"]),
        .init(id: "builder", title: "Builder", icon: "hammer.fill", colorHex: 0xFF7A59,
              pillars: ["Career", "Creativity"]),
    ]
}

/// Common ways people procrastinate — picked at onboarding so the coach can name
/// the pattern back to them.
enum ProcrastinationStyle: String, Codable, CaseIterable, Identifiable {
    case browsing, gaming, cleaning, research, planning, social, perfectionism
    var id: String { rawValue }
    var title: String {
        switch self {
        case .browsing: return "Browsing"
        case .gaming: return "Gaming"
        case .cleaning: return "Cleaning"
        case .research: return "Over-researching"
        case .planning: return "Over-planning"
        case .social: return "Social media"
        case .perfectionism: return "Perfectionism"
        }
    }
    var icon: String {
        switch self {
        case .browsing: return "safari.fill"
        case .gaming: return "gamecontroller.fill"
        case .cleaning: return "sparkles"
        case .research: return "magnifyingglass"
        case .planning: return "calendar"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .perfectionism: return "checkmark.seal.fill"
        }
    }
    /// A one-line nudge the coach can use.
    var nudge: String {
        switch self {
        case .browsing: return "When you catch yourself browsing, that's the cue to start the smallest step."
        case .gaming: return "Trade 10 minutes of the game for 10 minutes of the task — then decide."
        case .cleaning: return "Tidying is motion, not progress. The task first, the desk after."
        case .research: return "You know enough to start. The next answer is on the other side of doing."
        case .planning: return "The plan is good enough. Your next upgrade is execution."
        case .social: return "Park the scroll. One focused block, then it's yours guilt-free."
        case .perfectionism: return "Done beats perfect. Ship the rough version, refine later."
        }
    }
}

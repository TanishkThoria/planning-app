import SwiftUI

/// What the person is mainly using Chronos for. Drives the tone of the setup
/// recommendation; stored so the Coach can reference it too.
enum UserRole: String, CaseIterable, Identifiable, Codable {
    case student, professional, entrepreneur, creative, parent, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: return "Student"
        case .professional: return "Professional"
        case .entrepreneur: return "Founder / Freelancer"
        case .creative: return "Creative"
        case .parent: return "Parent / Home"
        case .general: return "A bit of everything"
        }
    }

    var icon: String {
        switch self {
        case .student: return "graduationcap.fill"
        case .professional: return "briefcase.fill"
        case .entrepreneur: return "chart.line.uptrend.xyaxis"
        case .creative: return "paintbrush.pointed.fill"
        case .parent: return "house.fill"
        case .general: return "sparkles"
        }
    }
}

/// The outcomes a person wants from Chronos. Each goal nominates the optional
/// modules that best serve it; the setup uses that to decide what to surface.
enum UserGoal: String, CaseIterable, Identifiable, Codable {
    case beatProcrastination
    case deepFocus
    case buildHabits
    case organizeSchedule
    case trackProgress
    case stayAccountable
    case balance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beatProcrastination: return "Stop procrastinating"
        case .deepFocus: return "Focus deeply"
        case .buildHabits: return "Build habits"
        case .organizeSchedule: return "Organize my schedule"
        case .trackProgress: return "Track my progress"
        case .stayAccountable: return "Stay accountable with friends"
        case .balance: return "Find work–life balance"
        }
    }

    var icon: String {
        switch self {
        case .beatProcrastination: return "bolt.fill"
        case .deepFocus: return "scope"
        case .buildHabits: return "leaf.fill"
        case .organizeSchedule: return "calendar"
        case .trackProgress: return "chart.bar.fill"
        case .stayAccountable: return "person.2.fill"
        case .balance: return "heart.fill"
        }
    }

    /// The optional modules this goal suggests promoting to a primary tab.
    var suggests: [PersonalModule] {
        switch self {
        case .beatProcrastination: return [.coach, .insights]
        case .deepFocus: return [.insights]
        case .buildHabits: return [.grow]
        case .organizeSchedule: return []
        case .trackProgress: return [.insights]
        case .stayAccountable: return [.coach]
        case .balance: return [.grow]
        }
    }
}

/// The optional feature areas that setup can promote to a primary tab or tuck
/// behind the "More" tab. Today, Calendar, and Tasks are always primary — the
/// core loop — so they aren't listed here.
enum PersonalModule: String, CaseIterable, Identifiable, Codable {
    case grow, insights, coach

    var id: String { rawValue }

    var screen: AppModel.Screen {
        switch self {
        case .grow: return .grow
        case .insights: return .insights
        case .coach: return .coach
        }
    }

    var title: String { screen.title }
    var icon: String { screen.icon }

    var blurb: String {
        switch self {
        case .grow: return "Habits, goals, rituals & reflection"
        case .insights: return "Momentum, streaks, trends & stats"
        case .coach: return "Your on-device AI planning companion"
        }
    }
}

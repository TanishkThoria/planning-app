import SwiftUI

/// A category for any event, task, or focus session — the layer that lets
/// Chronos (and the Coach) understand *what kind* of things you spend time on.
/// Every item gets one automatically from its title; you can override it.
enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case work, school, classes, study, chores, fitness, sports
    case social, health, errand, creative, meal, rest, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: return "Work"
        case .school: return "Schoolwork"
        case .classes: return "Class"
        case .study: return "Study"
        case .chores: return "Chores"
        case .fitness: return "Gym"
        case .sports: return "Sports"
        case .social: return "Social"
        case .health: return "Health"
        case .errand: return "Errands"
        case .creative: return "Creative"
        case .meal: return "Meal"
        case .rest: return "Rest"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .school: return "graduationcap.fill"
        case .classes: return "text.book.closed.fill"
        case .study: return "book.fill"
        case .chores: return "house.fill"
        case .fitness: return "dumbbell.fill"
        case .sports: return "sportscourt.fill"
        case .social: return "person.2.fill"
        case .health: return "heart.fill"
        case .errand: return "cart.fill"
        case .creative: return "paintbrush.pointed.fill"
        case .meal: return "fork.knife"
        case .rest: return "moon.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }

    var colorHex: UInt32 {
        switch self {
        case .work: return 0x5B8DEF
        case .school: return 0x7C6CF8
        case .classes: return 0x6C8CF8
        case .study: return 0x9B8CFF
        case .chores: return 0xB0895F
        case .fitness: return 0x2FBF71
        case .sports: return 0x2FA8BF
        case .social: return 0xF2719B
        case .health: return 0xFF6B6B
        case .errand: return 0xF2B95C
        case .creative: return 0xE07BE0
        case .meal: return 0xF2A65C
        case .rest: return 0x8A93A0
        case .other: return 0x9098A2
        }
    }

    var color: Color { Color(hex: colorHex) }

    /// Whether it counts as "productive" for balance insights.
    var isProductive: Bool {
        switch self {
        case .work, .school, .classes, .study, .creative, .chores, .errand: return true
        case .fitness, .sports, .health, .social, .meal, .rest, .other: return false
        }
    }

    // MARK: Auto-classification (keyword heuristic; the LLM Coach refines on top)

    /// Best-guess a category from a title. Order matters — more specific
    /// phrases are checked before generic ones (e.g. "dinner with" → social
    /// before "dinner" → meal).
    static func guess(from rawTitle: String) -> ActivityCategory? {
        let t = " " + rawTitle.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        if has([" with ", "party", "hang out", "hangout", "birthday", "coffee with", "lunch with", "dinner with", "drinks", "date night", "meetup", "meet up", "friends"]) { return .social }
        if has(["lecture", "seminar", "recitation", "office hours", "class ", " class", "cs1", "cs2", "biology", "chemistry", "physics", "calculus", "history class", "econ"]) { return .classes }
        if has(["homework", "assignment", "essay", "problem set", "pset", "exam", "midterm", "final exam", "quiz", "lab report", "study for", "revise for"]) { return .school }
        if has(["study", "flashcards", "review notes", "practice problems", "reading"]) { return .study }
        if has(["gym", "workout", "lift", "run", "jog", "yoga", "pilates", "exercise", "cardio", "cycling", "spin class"]) { return .fitness }
        if has(["practice", "scrimmage", "game", "match", "soccer", "basketball", "tennis", "volleyball", "hockey", "football", "swim", "track", "team"]) { return .sports }
        if has(["doctor", "dentist", "therapy", "therapist", "appointment", "clinic", "checkup", "medication", "physical"]) { return .health }
        if has(["groceries", "shopping", "bank", "post office", "pick up", "drop off", "errand", "haircut", "pharmacy", "oil change"]) { return .errand }
        if has(["clean", "laundry", "dishes", "chore", "tidy", "vacuum", "trash", "dust", "meal prep"]) { return .chores }
        if has(["draw", "paint", "sketch", "write ", "journal", "music", "guitar", "piano", "design", "photo", "video edit", "art"]) { return .creative }
        if has(["breakfast", "lunch", "dinner", "brunch", "meal", "snack"]) { return .meal }
        if has(["nap", "rest", "break", "relax", "meditate", "sleep", "wind down", "chill"]) { return .rest }
        if has(["work", "meeting", "standup", "stand-up", "1:1", "email", "project", "deadline", "client", "office", "sprint", "sync", "interview", "shift"]) { return .work }
        return nil
    }
}

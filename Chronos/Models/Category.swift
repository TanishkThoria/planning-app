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

        if has([" with ", "party", "hang out", "hangout", "birthday", "coffee with", "lunch with", "dinner with", "drinks", "date night", " date ", "meetup", "meet up", "friends", " friend", "catch up", "catch-up", "call with", "call home", "facetime", "phone call", "wedding", "reunion", "happy hour", "bar ", "night out", "visit ", "hangs", "girlfriend", "boyfriend", "roommate", "get together", "grab drinks", "brunch with"]) { return .social }
        if has(["lecture", "seminar", "recitation", "office hours", "class ", " class", "cs1", "cs2", "biology", "chemistry", "physics", "calculus", "history class", "econ", "tutorial", "discussion section", " course", "orgo", "organic chem", " bio ", " chem ", "math class", "english class", "professor", "section "]) { return .classes }
        if has(["homework", "assignment", "essay", "problem set", "pset", "exam", "midterm", "final exam", " finals", "quiz", "lab report", "study for", "revise for", "term paper", " paper", "thesis", "dissertation", "coursework", "submit ", "due:", "capstone", "research paper", "write-up", "writeup"]) { return .school }
        if has(["study", "flashcards", "review notes", "practice problems", "reading", "revise", "memorize", "anki", "prep for", "textbook", "review for", "cram"]) { return .study }
        if has(["gym", "workout", "work out", "lift", "lifting", "run ", " run", "jog", "yoga", "pilates", "exercise", "cardio", "cycling", "spin class", "hiit", "crossfit", "treadmill", "weights", "stretch", "hike", "hiking", "peloton", "walk", "steps", "training", "leg day", "push day", "pull day"]) { return .fitness }
        if has(["scrimmage", "soccer", "basketball", "tennis", "volleyball", "hockey", "football", "swim", "track meet", " team", "baseball", "golf", "climbing", "bouldering", "skiing", "snowboard", "lacrosse", "rugby", "cricket", "badminton", "tournament", "match ", " match", "practice", "pickleball", "ultimate"]) { return .sports }
        if has(["doctor", "dentist", "therapy", "therapist", "appointment", "clinic", "checkup", "check-up", "medication", "physical ", "hospital", "vaccine", "flu shot", "optometrist", "dermatologist", "counsel", "medical", " nurse", "blood test", "x-ray", "mri", "surgery", "urgent care", " appt"]) { return .health }
        if has(["groceries", "grocery", "shopping", " bank", "post office", "pick up", "pickup", "drop off", "dropoff", "errand", "haircut", "pharmacy", "oil change", " dmv", "mail ", "target run", "costco", "car wash", " gas ", "returns", "shipping", "package", "hardware store"]) { return .errand }
        if has(["clean", "laundry", "dishes", "chore", "tidy", "vacuum", "trash", "dust", "meal prep", "mow", "cook", "organize", "declutter", "sweep", " mop", "fold ", "garbage", "yard work", "dry cleaning", "wash the", "chores"]) { return .chores }
        if has(["draw", "paint", "sketch", "write ", "writing", "journal", " music", "guitar", "piano", "design", "photo", "video edit", " art", "blog", "compose", "podcast", " film", "editing", "record ", "craft", "knit", "sing", "produce", "sculpt", "animation", "portfolio"]) { return .creative }
        if has(["breakfast", "lunch", "dinner", "brunch", " meal", "snack", " eat", "coffee", " cafe", "restaurant", " food", "dining", "grab lunch", "grab food"]) { return .meal }
        if has(["nap", " rest", " break", "relax", "meditate", "sleep", "wind down", "chill", "unwind", "downtime", "decompress", " spa", " bath", " tv", "netflix", "gaming", "video game", "read for fun", "recharge", "lounge"]) { return .rest }
        if has(["work", "meeting", "standup", "stand-up", "1:1", "email", " project", "deadline", "client", "office", " sprint", " sync", "interview", "shift", "presentation", " report", " zoom", " slack", "retro", " demo", "onboarding", "invoice", "proposal", "stakeholder", "roadmap", "planning", "kickoff", "1-1", "check-in", "review "]) { return .work }
        return nil
    }
}

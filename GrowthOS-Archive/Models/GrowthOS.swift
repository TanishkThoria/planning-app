import Foundation
import SwiftUI

// The behavioural systems of Chronos 2.0: daily modes, the minimum-viable day,
// the personal operating manual, and the aspiration vault. All Codable with
// defaulted properties (older blobs decode), all owned by `LifeStore`.

// MARK: - Daily mode

/// How much the day is asking of the user — chosen each morning (or defaulted).
/// The planner and coach adapt their tone and targets to it, which is how
/// Chronos fights all-or-nothing thinking: a busy day isn't a failed day, it's a
/// Maintain day.
enum DailyMode: String, Codable, CaseIterable, Identifiable {
    case build, maintain, recover
    var id: String { rawValue }

    var title: String {
        switch self {
        case .build: return "Build"
        case .maintain: return "Maintain"
        case .recover: return "Recover"
        }
    }
    var tagline: String {
        switch self {
        case .build: return "High energy — make real progress"
        case .maintain: return "Busy day — protect consistency"
        case .recover: return "Low reserves — protect your health"
        }
    }
    var icon: String {
        switch self {
        case .build: return "flame.fill"
        case .maintain: return "shield.lefthalf.filled"
        case .recover: return "leaf.fill"
        }
    }
    var colorHex: UInt32 {
        switch self {
        case .build: return 0xFF7A59
        case .maintain: return 0x5B6CF0
        case .recover: return 0x5BD899
        }
    }
    var color: Color { Color(hex: colorHex) }

    /// Suggested number of must-win commitments for the day.
    var suggestedMustWins: Int {
        switch self {
        case .build: return 3
        case .maintain: return 2
        case .recover: return 1
        }
    }
    /// A gentle nudge shown when the mode is picked.
    var guidance: String {
        switch self {
        case .build: return "Pick your three needle-movers and go all in. Momentum compounds."
        case .maintain: return "Just keep the chain alive. One or two wins is a good day today."
        case .recover: return "Rest is productive. Choose one small win, then be kind to yourself."
        }
    }
}

// MARK: - Minimum viable day

/// One line of the day's plan — a must-win or a bonus. The point is to make the
/// floor explicit so a hard day still "counts."
struct IntentItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String = ""
    var isDone: Bool = false
    var doneEpoch: TimeInterval?
}

/// The per-day intention record: the mode, the must-wins ("the minimum version
/// of today that keeps you moving"), and the bonus list. One per calendar day.
struct DayIntent: Codable, Identifiable, Hashable {
    var id = UUID()
    var dayKey: String = ""                // yyyy-MM-dd
    var modeRaw: String?                   // DailyMode.rawValue, nil = unset
    var mustWins: [IntentItem] = []
    var bonuses: [IntentItem] = []
    var updatedEpoch: TimeInterval = 0

    var mode: DailyMode? { modeRaw.flatMap(DailyMode.init(rawValue:)) }
    var hasContent: Bool { !mustWins.isEmpty || !bonuses.isEmpty || modeRaw != nil }
    var mustWinsDone: Int { mustWins.filter(\.isDone).count }
    /// The floor is cleared when every must-win is done (and there's at least one).
    var floorCleared: Bool { !mustWins.isEmpty && mustWins.allSatisfy(\.isDone) }
}

// MARK: - Personal operating manual

/// The four sections of "My Manual" — the living document Chronos builds *with*
/// the user about how they actually work.
enum ManualCategory: String, Codable, CaseIterable, Identifiable {
    case principle, rule, pattern, solution
    var id: String { rawValue }

    var title: String {
        switch self {
        case .principle: return "Principles"
        case .rule: return "Rules"
        case .pattern: return "Patterns"
        case .solution: return "Solutions"
        }
    }
    var singular: String {
        switch self {
        case .principle: return "Principle"
        case .rule: return "Rule"
        case .pattern: return "Pattern"
        case .solution: return "Solution"
        }
    }
    var prompt: String {
        switch self {
        case .principle: return "What do you stand for? \"I prioritise deep work over busy work.\""
        case .rule: return "A line you don't cross. \"Never miss twice.\""
        case .pattern: return "A tendency you've noticed. \"I procrastinate when tasks feel ambiguous.\""
        case .solution: return "What actually works for you. \"Break tasks into the first physical action.\""
        }
    }
    var icon: String {
        switch self {
        case .principle: return "flag.fill"
        case .rule: return "shield.fill"
        case .pattern: return "waveform.path.ecg"
        case .solution: return "wrench.and.screwdriver.fill"
        }
    }
    var colorHex: UInt32 {
        switch self {
        case .principle: return 0x5B6CF0
        case .rule: return 0xFF6B6B
        case .pattern: return 0xFFB23E
        case .solution: return 0x3FC97A
        }
    }
    var color: Color { Color(hex: colorHex) }
}

/// One entry in the personal operating manual.
struct ManualNote: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: ManualCategory = .principle
    var text: String = ""
    var createdEpoch: TimeInterval = 0
    var updatedEpoch: TimeInterval?
    var isArchived: Bool = false
}

// MARK: - Aspiration vault

/// Something the user desires to own or experience — but reframed. Each item must
/// answer *what version of yourself it represents* and *what evidence you're
/// building toward it*, turning a distraction into a symbol of growth.
struct Aspiration: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var emoji: String = "✨"
    var colorHex: UInt32 = Palette.options[2]
    var meaning: String = ""               // "what version of yourself does this represent?"
    var priceNote: String = ""             // optional cost / savings target, freeform
    var linkedPillarID: UUID?              // the identity it symbolises
    var linkedGoalID: UUID?               // a savings / career goal it depends on
    var savedEpoch: TimeInterval = 0
    var acquiredEpoch: TimeInterval?       // marked when earned
    var isArchived: Bool = false

    var color: Color { Palette.color(colorHex) }
    var isAcquired: Bool { acquiredEpoch != nil }
    var savedDate: Date { Date(timeIntervalSince1970: savedEpoch) }
}

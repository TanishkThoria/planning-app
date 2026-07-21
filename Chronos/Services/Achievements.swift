import SwiftUI

/// Bronze / Silver / Gold — a badge's weight, for color and a sense of climb.
enum AchievementTier: String {
    case bronze, silver, gold

    var label: String { rawValue.capitalized }
    var colorHex: UInt32 {
        switch self {
        case .bronze: return 0xCD8B5A
        case .silver: return 0xB9C2CF
        case .gold:   return 0xF2C14E
        }
    }
    var color: Color { Color(hex: colorHex) }
}

/// Lightweight gamification: badges computed from real behaviour. Purely
/// derived (never stored), so they can't drift from the underlying data. Each
/// carries a plain-language description of how it's earned and why it matters.
struct Achievement: Identifiable {
    let id: String
    let title: String
    /// Short line shown under the badge / in the celebration.
    let detail: String
    let icon: String
    let tier: AchievementTier
    let unlocked: Bool
    /// 0…1 progress toward unlocking (1 when unlocked).
    let progress: Double
    /// "3 / 7 days" style progress text for the locked state.
    let progressText: String
}

enum AchievementEngine {

    struct Inputs {
        var completionStreak: Int
        var totalFocusMinutes: Int
        var weekDeepMinutes: Int
        var onTimeRate: Double
        var datedCompleted: Int
        var bestHabitStreak: Int
        var journalStreak: Int
        var templatesSaved: Int
        var weekBlockCount: Int
        // Momentum & routines (gamification layer)
        var momentumLevel: Int = 1
        var momentumStreak: Int = 0
        var perfectDays: Int = 0
        var solidDays: Int = 0
        var bestRoutineStreak: Int = 0
    }

    static func compute(_ i: Inputs) -> [Achievement] {
        func badge(_ id: String, _ title: String, _ detail: String, _ icon: String,
                   _ tier: AchievementTier, _ value: Double, _ target: Double,
                   unit: String = "") -> Achievement {
            let done = value >= target
            let text: String
            if done {
                text = "Unlocked"
            } else if unit.isEmpty {
                text = "\(Int(min(value, target)))/\(Int(target))"
            } else {
                text = "\(Int(min(value, target)))/\(Int(target)) \(unit)"
            }
            return Achievement(
                id: id, title: title, detail: detail, icon: icon, tier: tier,
                unlocked: done,
                progress: target <= 0 ? 1 : min(1, value / target),
                progressText: text
            )
        }

        return [
            // Consistency
            badge("streak3", "Getting Going", "Complete something 3 days running.", "sparkles",
                  .bronze, Double(i.completionStreak), 3, unit: "days"),
            badge("streak7", "Consistent", "A full week without missing a day.", "flame.fill",
                  .silver, Double(i.completionStreak), 7, unit: "days"),
            badge("streak30", "Unstoppable", "Thirty days straight. This is who you are now.", "bolt.fill",
                  .gold, Double(i.completionStreak), 30, unit: "days"),
            // Focus
            badge("focus10", "Focused", "Bank 10 hours on the focus timer.", "timer",
                  .bronze, Double(i.totalFocusMinutes), 600, unit: "min"),
            badge("focus50", "Deep Work Machine", "Fifty hours of tracked focus. Rare air.", "gauge.high",
                  .gold, Double(i.totalFocusMinutes), 3000, unit: "min"),
            badge("deep5", "Deep Diver", "5 hours of deep work in one week.", "brain.head.profile",
                  .silver, Double(i.weekDeepMinutes), 300, unit: "min"),
            // Reliability
            badge("ontime", "Dependable", "Hit 90% on-time across 5+ dated tasks.", "checkmark.seal.fill",
                  .silver, i.datedCompleted >= 5 ? i.onTimeRate : 0, 0.9),
            // Habits & routines
            badge("habit14", "Habit Former", "Keep a habit alive for 14 days.", "repeat.circle.fill",
                  .silver, Double(i.bestHabitStreak), 14, unit: "days"),
            badge("habit60", "Second Nature", "A 60-day habit streak. It's automatic now.", "infinity.circle.fill",
                  .gold, Double(i.bestHabitStreak), 60, unit: "days"),
            badge("routine7", "Ritualist", "Run a tracked routine 7 days in a row.", "figure.walk.motion",
                  .silver, Double(i.bestRoutineStreak), 7, unit: "days"),
            // Reflection & planning
            badge("reflect5", "Reflective", "Journal 5 evenings in a row.", "book.closed.fill",
                  .bronze, Double(i.journalStreak), 5, unit: "days"),
            badge("architect", "Architect", "Save a reusable day template.", "square.grid.3x3.fill",
                  .bronze, Double(i.templatesSaved), 1),
            badge("builder", "Builder", "Plan 20 blocks in a single week.", "square.stack.3d.up.fill",
                  .silver, Double(i.weekBlockCount), 20, unit: "blocks"),
            // Momentum
            badge("level3", "In the Zone", "Reach momentum level 3.", "chart.line.uptrend.xyaxis",
                  .bronze, Double(i.momentumLevel), 3),
            badge("level10", "Peak Performer", "Reach momentum level 10.", "crown.fill",
                  .gold, Double(i.momentumLevel), 10),
            badge("mstreak14", "On a Roll", "14-day momentum streak.", "flame.circle.fill",
                  .silver, Double(i.momentumStreak), 14, unit: "days"),
            badge("perfect", "Perfect Day", "Score a full 100 momentum in a day.", "star.circle.fill",
                  .gold, Double(i.perfectDays), 1),
            badge("solid30", "Locked In", "30 solid-momentum days banked.", "shield.lefthalf.filled",
                  .gold, Double(i.solidDays), 30, unit: "days"),
        ]
    }
}

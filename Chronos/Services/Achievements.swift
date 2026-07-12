import SwiftUI

/// Lightweight gamification: badges computed from real behaviour. Purely
/// derived (never stored), so they can't drift from the underlying data.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let unlocked: Bool
    /// 0…1 progress toward unlocking (1 when unlocked).
    let progress: Double
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
    }

    static func compute(_ i: Inputs) -> [Achievement] {
        func badge(_ id: String, _ title: String, _ detail: String, _ icon: String,
                   _ value: Double, _ target: Double) -> Achievement {
            Achievement(
                id: id, title: title, detail: detail, icon: icon,
                unlocked: value >= target,
                progress: target <= 0 ? 1 : min(1, value / target)
            )
        }

        return [
            badge("streak7", "Consistent", "7-day completion streak", "flame.fill",
                  Double(i.completionStreak), 7),
            badge("streak30", "Unstoppable", "30-day completion streak", "bolt.fill",
                  Double(i.completionStreak), 30),
            badge("focus10", "Focused", "10 hours of timed focus", "timer",
                  Double(i.totalFocusMinutes), 600),
            badge("deep5", "Deep Diver", "5 hours of deep work this week", "brain.head.profile",
                  Double(i.weekDeepMinutes), 300),
            badge("ontime", "Dependable", "90% on-time on 5+ dated tasks", "checkmark.seal.fill",
                  i.datedCompleted >= 5 ? i.onTimeRate : 0, 0.9),
            badge("habit14", "Habit Former", "14-day habit streak", "repeat.circle.fill",
                  Double(i.bestHabitStreak), 14),
            badge("reflect5", "Reflective", "5-day journaling streak", "book.closed.fill",
                  Double(i.journalStreak), 5),
            badge("architect", "Architect", "Saved a day template", "square.grid.3x3.fill",
                  Double(i.templatesSaved), 1),
            badge("builder", "Builder", "20 blocks planned in a week", "square.stack.3d.up.fill",
                  Double(i.weekBlockCount), 20),
        ]
    }
}

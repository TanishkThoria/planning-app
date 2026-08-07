import Foundation

// Numbers rarely move people; meaning does. NarrativeStats turns raw totals into
// sentences a human feels — "243 focus hours" becomes "six full workweeks spent
// becoming better at your craft." Pure and deterministic.

struct StatStory: Identifiable {
    let id = UUID()
    let icon: String
    let tintHex: UInt32
    let text: String
}

enum NarrativeStats {

    /// The lifetime headline: what all that focus time really amounts to.
    static func focusLifetime(minutes: Int) -> StatStory? {
        guard minutes >= 60 else { return nil }
        let hours = Double(minutes) / 60
        let text: String
        if hours >= 40 {
            let weeks = hours / 40
            text = String(format: "You've focused for %@ — the equivalent of %.1f full work-weeks spent becoming who you want to be.",
                          Fmt.duration(minutes: minutes), weeks)
        } else if hours >= 8 {
            let days = hours / 8
            text = String(format: "You've focused for %@ — about %.1f full working days of deep, deliberate effort.",
                          Fmt.duration(minutes: minutes), days)
        } else {
            text = "You've focused for \(Fmt.duration(minutes: minutes)) — every block a vote for the person you're becoming."
        }
        return StatStory(icon: "timer", tintHex: 0xFF7A59, text: text)
    }

    /// This week's story: a few human sentences from the week's numbers.
    static func week(focusMinutes: Int, tasksCompleted: Int, plannedMinutes: Int,
                     blockCount: Int, streakDays: Int) -> [StatStory] {
        var out: [StatStory] = []
        if tasksCompleted > 0 {
            out.append(StatStory(icon: "checkmark.circle.fill", tintHex: 0x3FC97A,
                text: "You turned \(tasksCompleted) intention\(tasksCompleted == 1 ? "" : "s") into done this week."))
        }
        if plannedMinutes >= 60 {
            out.append(StatStory(icon: "rectangle.stack.fill", tintHex: 0x5B6CF0,
                text: "You designed \(Fmt.duration(minutes: plannedMinutes)) of intentional time instead of letting the week happen to you."))
        }
        if focusMinutes >= 25 {
            out.append(StatStory(icon: "brain.head.profile", tintHex: 0x9C7BFA,
                text: "You gave \(Fmt.duration(minutes: focusMinutes)) of undistracted attention to what matters."))
        }
        if streakDays >= 2 {
            out.append(StatStory(icon: "flame.fill", tintHex: 0xFFB23E,
                text: "\(streakDays) days in a row of showing up — consistency is the whole game."))
        }
        return out
    }
}

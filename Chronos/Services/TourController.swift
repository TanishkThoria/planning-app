import SwiftUI

/// Drives the interactive product tour: it walks the user through the real
/// screens of the app (switching tabs and modes for them) and, on each step,
/// can trigger the actual feature so they see it work — not a slideshow, the
/// live app with a guided spotlight.
@MainActor
final class TourController: ObservableObject {
    static let shared = TourController()
    private init() {}

    @Published var isActive = false
    @Published var index = 0

    let steps = TourStep.all

    var current: TourStep? { steps.indices.contains(index) ? steps[index] : nil }
    var progress: Double { steps.isEmpty ? 0 : Double(index + 1) / Double(steps.count) }
    var isLast: Bool { index >= steps.count - 1 }

    func start() {
        index = 0
        isActive = true
    }

    func next() {
        if index + 1 < steps.count {
            index += 1
        } else {
            finish()
        }
    }

    func back() {
        if index > 0 { index -= 1 }
    }

    func finish() {
        isActive = false
        index = 0
    }
}

/// One stop on the tour. `screen`/`mode` navigate the real app; `demo` fires
/// the actual feature when the user taps "Show me".
struct TourStep: Identifiable {
    let id = UUID()
    let screen: AppModel.Screen
    var mode: AppModel.PlannerMode?
    let icon: String
    let title: String
    let message: String
    var demoLabel: String?
    var demo: TourDemo?

    static let all: [TourStep] = [
        TourStep(
            screen: .today,
            icon: "sun.max.fill",
            title: "Today, at a glance",
            message: "Your home base — what's now, what's next, and what's left. The labeled row up top runs your day: Plan, Reflow, Review, Focus, Now, and Coach.",
            demoLabel: "Quick-add anything",
            demo: .quickAdd
        ),
        TourStep(
            screen: .calendar, mode: .day,
            icon: "calendar.day.timeline.left",
            title: "The day timeline",
            message: "Every block is a real Apple Calendar event. Double-tap an empty slot to create one; drag to move or resize. The action row under the tabs plans, reviews, and applies templates.",
            demoLabel: "Plan my day for me",
            demo: .planDay
        ),
        TourStep(
            screen: .calendar, mode: .week,
            icon: "calendar",
            title: "Zoom out to the week",
            message: "Switch modes up top. Week shows all seven days on one scale so you can balance your load.",
            demoLabel: nil,
            demo: nil
        ),
        TourStep(
            screen: .calendar, mode: .month,
            icon: "square.grid.3x3",
            title: "Month & agenda",
            message: "Step back to the month for the big picture, or use Agenda for a clean, scannable list of what's ahead.",
            demoLabel: nil,
            demo: nil
        ),
        TourStep(
            screen: .tasks,
            icon: "checklist",
            title: "Tasks, your way",
            message: "Your Apple Reminders with estimates, energy, and priority. Toggle the Eisenhower matrix to triage what truly matters.",
            demoLabel: "Search everything",
            demo: .search
        ),
        TourStep(
            screen: .grow,
            icon: "leaf.fill",
            title: "Grow every day",
            message: "Habits, goals, a journal, and morning & evening rituals — the part of you behind the schedule.",
            demoLabel: "Try a morning ritual",
            demo: .morningRitual
        ),
        TourStep(
            screen: .insights,
            icon: "chart.bar.fill",
            title: "Insights — your progress",
            message: "Everything you build shows up here: momentum, this week at a glance, full statistics, where your time went, long-term trends, your Year in Review, and the friends leaderboard.",
            demoLabel: "Open Statistics",
            demo: .stats
        ),
        TourStep(
            screen: .today,
            icon: "sparkles",
            title: "Meet your Coach",
            message: "Your planning companion is a tap away — from Today's action row or the ⌘K command bar. Ask anything about your day; it answers from your real schedule and plans it with a tap.",
            demoLabel: "Open the Coach",
            demo: .coach
        ),
        TourStep(
            screen: .today,
            icon: "timer",
            title: "Focus when it counts",
            message: "Start a Pomodoro or open timer anytime. It rides along on your Lock Screen and Dynamic Island as a Live Activity.",
            demoLabel: "Start a focus session",
            demo: .focusTimer
        ),
        TourStep(
            screen: .today,
            icon: "command",
            title: "Anything, one keystroke away",
            message: "Press ⌘K (or tap the ⌘ button) to jump to any screen or run any action — including Chronos+ for iCloud sync, leaderboards, and friends. That's the whole tour!",
            demoLabel: "Open the command bar",
            demo: .commandBar
        )
    ]
}

enum TourDemo {
    case quickAdd, planDay, focusTimer, morningRitual, search, stats, coach, commandBar
}

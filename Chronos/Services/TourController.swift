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
            title: "Today — your home base",
            message: "What's next, what's overdue, your frog, intentions and habits, all on one screen. The ••• menu up top holds Plan Today, Review, Reflow, and Focus; the + button quick-adds anything.",
            demoLabel: "Try quick-add",
            demo: .quickAdd
        ),
        TourStep(
            screen: .calendar, mode: .day,
            icon: "calendar.day.timeline.left",
            title: "The day timeline",
            message: "Every block is a real Apple Calendar event. Double-tap an empty slot to create one; drag to move or resize. The ••• menu is your planning toolkit — Plan My Day, Templates, Deadlines, and more.",
            demoLabel: "Plan my day for me",
            demo: .planDay
        ),
        TourStep(
            screen: .calendar, mode: .week,
            icon: "calendar",
            title: "Day · Week · Month · Agenda",
            message: "One Calendar tab, four views — switch with the segmented control. Week balances your load across seven days; Month is the big picture; Agenda is a clean scannable list.",
            demoLabel: nil,
            demo: nil
        ),
        TourStep(
            screen: .tasks,
            icon: "checklist",
            title: "Tasks & the matrix",
            message: "Your Apple Reminders with estimates, energy, and priority. Flip to the Eisenhower Matrix with the toggle up top. The ••• menu has Plan Deadlines and Sweep Overdue for when things pile up.",
            demoLabel: "Search everything",
            demo: .search
        ),
        TourStep(
            screen: .grow,
            icon: "leaf.fill",
            title: "Grow every day",
            message: "Habits with streaks, goals, and a journal. The ••• menu opens your morning & evening rituals, the Weekly Review, and long-term Trends. The + button adds a goal or habit.",
            demoLabel: "Try a morning ritual",
            demo: .morningRitual
        ),
        TourStep(
            screen: .coach,
            icon: "sparkles",
            title: "Coach — ask & reflect",
            message: "Ask anything about your day; it answers from your real schedule and plans it with a tap. Its ••• menu is your Insights & Reports home — Statistics, Time Report, Budgets, Trends, and Year in Review all live here.",
            demoLabel: "Open your Statistics",
            demo: .stats
        ),
        TourStep(
            screen: .today,
            icon: "timer",
            title: "Focus & Now mode",
            message: "Start a Pomodoro or open timer from any block or task — it rides along on your Lock Screen as a Live Activity. Need zero distractions? Now mode strips everything down to just this moment.",
            demoLabel: "Start a focus session",
            demo: .focusTimer
        ),
        TourStep(
            screen: .today,
            icon: "command",
            title: "Find anything, instantly",
            message: "Two things to remember: every screen's ••• menu ends with Command Bar, Search, Settings, and this Tour — and the Command Bar (⌘K) jumps to any action in one keystroke. Settings groups your reports, planning tools, school connect, and Chronos+. That's the tour!",
            demoLabel: "Open the Command Bar",
            demo: .commandBar
        )
    ]
}

enum TourDemo {
    case quickAdd, planDay, focusTimer, morningRitual, search, stats, commandBar
}

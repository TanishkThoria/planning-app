import SwiftUI
import Combine

/// UI-level state: which screen is showing, which date is selected, which
/// sheets are open. Preferences live in `@AppStorage` (see `Prefs`) so any
/// view can bind to them directly; calendar visibility is persisted here
/// because `Set<String>` doesn't fit AppStorage.
@MainActor
final class AppModel: ObservableObject {

    enum Screen: String, CaseIterable, Identifiable {
        case today
        case calendar
        case tasks
        case grow
        case insights
        case coach
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .calendar: return "Calendar"
            case .tasks: return "Tasks"
            case .grow: return "Grow"
            case .insights: return "Insights"
            case .coach: return "Coach"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .calendar: return "calendar"
            case .tasks: return "checklist"
            case .grow: return "leaf"
            case .insights: return "chart.bar"
            case .coach: return "lightbulb"
            case .settings: return "gearshape"
            }
        }

        /// Filled variant for the iOS tab bar selected state.
        var iconFilled: String {
            switch self {
            case .today: return "sun.max.fill"
            case .calendar: return "calendar"
            case .tasks: return "checklist.checked"
            case .grow: return "leaf.fill"
            case .insights: return "chart.bar.fill"
            case .coach: return "lightbulb.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var shortcut: KeyEquivalent? {
            switch self {
            case .today: return "1"
            case .calendar: return "2"
            case .tasks: return "3"
            case .grow: return "4"
            case .insights: return "5"
            case .coach: return "6"
            case .settings: return nil
            }
        }

        /// Screens listed in the macOS/iPad sidebar (Coach and Settings are
        /// full rows here; on iPhone they're reached other ways).
        static let sidebarCases: [Screen] = [.today, .calendar, .tasks, .grow, .insights, .coach, .settings]
        /// The five primary iPhone tabs. Coach moved off the tab bar (it's
        /// reached from Today's action row and the command bar) so Insights —
        /// where all your progress lives — earns a permanent home. Settings is
        /// a toolbar gear; Matrix is a mode inside Tasks. Nothing hides behind
        /// a "More" overflow.
        static let compactTabs: [Screen] = [.today, .calendar, .tasks, .grow, .insights]
    }

    /// The three ways of viewing the calendar, switched with a segmented
    /// control inside the Calendar screen.
    enum PlannerMode: String, CaseIterable, Identifiable {
        case day, week, month, agenda
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            case .agenda: return "Agenda"
            }
        }
        var icon: String {
            switch self {
            case .day: return "calendar.day.timeline.left"
            case .week: return "calendar"
            case .month: return "calendar"
            case .agenda: return "list.bullet.rectangle"
            }
        }
    }

    @Published var screen: Screen = .today
    @Published var plannerMode: PlannerMode = .day
    @Published var selectedDate: Date = Date().startOfDay

    // Sheets
    @Published var quickAddPresented = false
    @Published var planDayPresented = false
    @Published var planWeekPresented = false
    @Published var calibrationPresented = false
    @Published var morningPlanningPresented = false
    @Published var reviewPresented = false
    @Published var reflowPresented = false
    /// iOS presents Settings as a sheet (macOS uses the sidebar + ⌘,).
    @Published var settingsPresented = false
    @Published var focusTimerPresented = false
    @Published var focusTimerContext: FocusStartContext?
    @Published var blockEditor: BlockEditorContext?
    @Published var taskEditor: TaskEditorContext?

    // Lifestyle sheets
    @Published var goalEditor: GoalEditContext?
    @Published var habitEditor: HabitEditContext?
    @Published var journalPresented = false
    @Published var morningRitualPresented = false
    @Published var eveningRitualPresented = false
    @Published var weeklyReviewPresented = false
    @Published var templatesPresented = false
    @Published var budgetsPresented = false
    @Published var calendarFilterPresented = false
    @Published var searchPresented = false
    @Published var overdueSweepPresented = false
    /// Detailed account statistics (relocated out of the primary tabs).
    @Published var statsPresented = false
    /// Universal command bar (⌘K).
    @Published var commandBarPresented = false
    /// Action deferred until the command bar sheet finishes dismissing, so we
    /// never try to present two sheets at once.
    var pendingCommandBarAction: (() -> Void)?
    /// Prefill text handed to Quick Add (e.g. from the command bar).
    var quickAddPrefill: String?
    /// School LMS (Canvas/Schoology) connect flow.
    @Published var lmsSetupPresented = false
    /// LMS management (connected schools, sync, unlink).
    @Published var lmsManagePresented = false
    /// Deadline work-back study planner.
    @Published var deadlinePlanPresented = false
    /// "Copy availability" free-slot composer.
    @Published var availabilityPresented = false
    /// Long-horizon growth trends (mood, habits, goals, reflections).
    @Published var trendsPresented = false
    /// Where-did-my-time-go report.
    @Published var timeReportPresented = false
    /// Year in Review / Wrapped.
    @Published var wrappedPresented = false
    /// Distraction-free "Now" focus mode.
    @Published var nowModePresented = false
    /// Momentum deep-dive (streaks, freezes, tips).
    @Published var momentumDetailPresented = false
    /// Chronos+ hub (iCloud sync, leaderboards, friends).
    @Published var chronosPlusPresented = false
    /// Game Center leaderboard (Chronos+).
    @Published var leaderboardPresented = false
    /// Friends presence (Chronos+).
    @Published var friendsPresented = false
    /// The Coach, presented as a sheet on iPhone (it's a sidebar screen on
    /// iPad/Mac). Reached from Today's action row and the command bar.
    @Published var coachPresented = false

    /// Show/hide the backlog rail in the day planner (wide layouts).
    @Published var backlogVisible = true

    // MARK: Eat the frog (the one task you're most likely to avoid)

    private static let frogIDKey = "state.frogTaskID"
    private static let frogDayKey = "state.frogDay"

    /// Today's frog — reset automatically each day.
    @Published var frogTaskID: String? {
        didSet {
            UserDefaults.standard.set(frogTaskID, forKey: Self.frogIDKey)
            UserDefaults.standard.set(Fmt.dayKey(Date()), forKey: Self.frogDayKey)
        }
    }

    // MARK: Calendar visibility (persisted manually)

    private static let hiddenCalendarsKey = "state.hiddenCalendarIDs"
    private static let hiddenListsKey = "state.hiddenListIDs"

    @Published var hiddenCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenCalendarsKey) }
    }
    @Published var hiddenListIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenListIDs), forKey: Self.hiddenListsKey) }
    }

    init() {
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        hiddenListIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenListsKey) ?? [])
        // A frog only lives for a day.
        if UserDefaults.standard.string(forKey: Self.frogDayKey) == Fmt.dayKey(Date()) {
            frogTaskID = UserDefaults.standard.string(forKey: Self.frogIDKey)
        }
    }

    func toggleCalendar(_ id: String) {
        if hiddenCalendarIDs.contains(id) { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
    }

    func toggleList(_ id: String) {
        if hiddenListIDs.contains(id) { hiddenListIDs.remove(id) } else { hiddenListIDs.insert(id) }
    }

    // MARK: Navigation

    func goToToday() {
        selectedDate = Date().startOfDay
    }

    /// Week steps a week; month steps a month; day and agenda step a day.
    private var navStride: Int {
        (screen == .calendar && plannerMode == .week) ? 7 : 1
    }

    func goForward() {
        if screen == .calendar && plannerMode == .month {
            selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        } else {
            selectedDate = selectedDate.adding(days: navStride)
        }
    }

    func goBackward() {
        if screen == .calendar && plannerMode == .month {
            selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        } else {
            selectedDate = selectedDate.adding(days: -navStride)
        }
    }

    /// Jump to a specific day and show it in the day planner.
    func openDay(_ date: Date) {
        selectedDate = date.startOfDay
        plannerMode = .day
        screen = .calendar
    }

    // MARK: Sheet launchers

    func newBlock(at start: Date? = nil, defaultMinutes: Int = 30, calendarID: String? = nil) {
        var draft = BlockDraft()
        if let start {
            draft.start = start
            draft.end = start.adding(minutes: defaultMinutes)
        } else {
            let slot = selectedDate.isToday ? Date.nextCleanSlot() : selectedDate.at(minutes: 9 * 60)
            draft.start = slot
            draft.end = slot.adding(minutes: defaultMinutes)
        }
        draft.calendarID = calendarID
        blockEditor = BlockEditorContext(draft: draft, existingID: nil)
    }

    func newTask(listID: String? = nil) {
        var draft = TaskDraft()
        draft.listID = listID
        taskEditor = TaskEditorContext(draft: draft, existingID: nil)
    }

    func startFocus(taskID: String?, title: String) {
        focusTimerContext = FocusStartContext(taskID: taskID, title: title)
        focusTimerPresented = true
    }

    /// Routes a `chronos://…` deep link from a widget, Live Activity, or
    /// Shortcut to the right place in the app.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "chronos" else { return }
        switch url.host {
        case "today", nil:
            screen = .today
        case "focus":
            screen = .today
            focusTimerPresented = true
        case "tasks":
            screen = .tasks
        case "calendar":
            screen = .calendar
        case "grow":
            screen = .grow
        case "insights":
            screen = .insights
        case "coach":
            screen = .coach
        case "add":
            quickAddPresented = true
        case "plan":
            screen = .today
            morningPlanningPresented = true
        default:
            screen = .today
        }
    }
}

/// Seeds the focus timer sheet with an optional task to work on.
struct FocusStartContext {
    var taskID: String?
    var title: String
}

struct GoalEditContext: Identifiable {
    let id = UUID()
    var goal: Goal
    var isNew: Bool
}

struct HabitEditContext: Identifiable {
    let id = UUID()
    var habit: Habit
    var isNew: Bool
}

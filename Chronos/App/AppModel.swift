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
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .calendar: return "Calendar"
            case .tasks: return "Tasks"
            case .grow: return "Grow"
            case .insights: return "Insights"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .calendar: return "calendar"
            case .tasks: return "checklist"
            case .grow: return "leaf"
            case .insights: return "chart.bar.xaxis"
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
            case .insights: return "chart.bar.xaxis"
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
            case .settings: return nil
            }
        }

        /// Screens listed in the macOS/iPad sidebar.
        static let sidebarCases: [Screen] = [.today, .calendar, .tasks, .grow, .insights, .settings]
        /// The five primary iPhone tabs — Settings is reached from a toolbar
        /// gear, so nothing hides behind a "More" overflow. (Matrix lives as
        /// a mode inside Tasks.)
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

    /// Show/hide the backlog rail in the day planner (wide layouts).
    @Published var backlogVisible = true

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

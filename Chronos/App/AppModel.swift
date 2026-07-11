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
        case day
        case week
        case agenda
        case tasks
        case matrix
        case insights
        case settings
        /// iPhone-only overflow tab hosting the screens that don't fit the bar.
        case more

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .day: return "Day"
            case .week: return "Week"
            case .agenda: return "Agenda"
            case .tasks: return "Tasks"
            case .matrix: return "Matrix"
            case .insights: return "Insights"
            case .settings: return "Settings"
            case .more: return "More"
            }
        }

        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .day: return "calendar.day.timeline.left"
            case .week: return "calendar"
            case .agenda: return "list.bullet.rectangle"
            case .tasks: return "checklist"
            case .matrix: return "square.grid.2x2"
            case .insights: return "chart.bar.xaxis"
            case .settings: return "gearshape"
            case .more: return "ellipsis.circle"
            }
        }

        var shortcut: KeyEquivalent? {
            switch self {
            case .today: return "1"
            case .day: return "2"
            case .week: return "3"
            case .agenda: return "4"
            case .tasks: return "5"
            case .matrix: return "6"
            case .insights: return "7"
            case .settings, .more: return nil
            }
        }

        /// Screens listed in the macOS/iPad sidebar.
        static let sidebarCases: [Screen] = [.today, .day, .week, .agenda, .tasks, .matrix, .insights, .settings]
        /// Tabs shown on compact iPhone layouts (the rest live under More).
        static let compactTabs: [Screen] = [.today, .day, .tasks, .matrix, .more]
    }

    @Published var screen: Screen = .today
    @Published var selectedDate: Date = Date().startOfDay

    // Sheets
    @Published var quickAddPresented = false
    @Published var planDayPresented = false
    @Published var planWeekPresented = false
    @Published var calibrationPresented = false
    @Published var morningPlanningPresented = false
    @Published var reviewPresented = false
    @Published var focusTimerPresented = false
    @Published var focusTimerContext: FocusStartContext?
    @Published var blockEditor: BlockEditorContext?
    @Published var taskEditor: TaskEditorContext?

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

    func goForward() {
        selectedDate = selectedDate.adding(days: screen == .week ? 7 : 1)
    }

    func goBackward() {
        selectedDate = selectedDate.adding(days: screen == .week ? -7 : -1)
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

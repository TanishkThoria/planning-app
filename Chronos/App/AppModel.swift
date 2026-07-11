import SwiftUI
import Combine

/// UI-level state: which screen is showing, which date is selected, which
/// sheets are open. Preferences live in `@AppStorage` (see `Prefs`) so any
/// view can bind to them directly; calendar visibility is persisted here
/// because `Set<String>` doesn't fit AppStorage.
@MainActor
final class AppModel: ObservableObject {

    enum Screen: String, CaseIterable, Identifiable {
        case day
        case week
        case tasks
        case insights
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .tasks: return "Tasks"
            case .insights: return "Insights"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .day: return "calendar.day.timeline.left"
            case .week: return "calendar"
            case .tasks: return "checklist"
            case .insights: return "chart.bar.xaxis"
            case .settings: return "gearshape"
            }
        }

        var shortcut: KeyEquivalent? {
            switch self {
            case .day: return "1"
            case .week: return "2"
            case .tasks: return "3"
            case .insights: return "4"
            case .settings: return nil
            }
        }
    }

    @Published var screen: Screen = .day
    @Published var selectedDate: Date = Date().startOfDay

    // Sheets
    @Published var quickAddPresented = false
    @Published var planDayPresented = false
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
}

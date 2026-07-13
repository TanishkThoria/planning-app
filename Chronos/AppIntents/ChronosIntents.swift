import AppIntents
import EventKit

/// Siri + Shortcuts entry points. These run in-process, talk to EventKit
/// directly, and need no separate extension — so "Hey Siri, timeblock deep
/// work" or a Shortcuts automation can create blocks and tasks without
/// opening the app.

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case calendarAccessDenied
    case remindersAccessDenied
    case noWritableCalendar
    case noWritableList

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .calendarAccessDenied: return "Chronos needs Calendar access to create a block."
        case .remindersAccessDenied: return "Chronos needs Reminders access to add a task."
        case .noWritableCalendar: return "No writable calendar is available."
        case .noWritableList: return "No writable reminder list is available."
        }
    }
}

/// "Timeblock deep work at 2pm for 90 minutes."
struct TimeblockIntent: AppIntent {
    static var title: LocalizedStringResource = "Create a Time Block"
    static var description = IntentDescription(
        "Adds a time block to your calendar.",
        categoryName: "Planning"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Title", requestValueDialog: "What should the block be called?")
    var blockTitle: String

    @Parameter(title: "Start")
    var start: Date?

    @Parameter(title: "Duration (minutes)", default: 30)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Timeblock \(\.$blockTitle) for \(\.$minutes) minutes starting \(\.$start)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else {
            throw IntentError.calendarAccessDenied
        }
        guard let calendar = store.defaultCalendarForNewEvents
                ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            throw IntentError.noWritableCalendar
        }

        let startDate = (start ?? Date.nextCleanSlot()).snapped(to: 5)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = blockTitle
        event.startDate = startDate
        event.endDate = startDate.adding(minutes: max(minutes, 5))
        try store.save(event, span: .thisEvent, commit: true)

        return .result(dialog: "Blocked \(blockTitle) at \(Fmt.time.string(from: startDate)).")
    }
}

/// "Add a reminder to call the dentist."
struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Task"
    static var description = IntentDescription(
        "Adds a task to Apple Reminders.",
        categoryName: "Planning"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What do you need to do?")
    var taskTitle: String

    @Parameter(title: "Due")
    var due: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add task \(\.$taskTitle) due \(\.$due)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else {
            throw IntentError.remindersAccessDenied
        }
        guard let list = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) else {
            throw IntentError.noWritableList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = taskTitle
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        try store.save(reminder, commit: true)

        return .result(dialog: "Added “\(taskTitle)” to your reminders.")
    }
}

/// Opens the app straight into the morning planning ritual.
struct PlanTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan Today"
    static var description = IntentDescription("Opens Chronos to plan your day.", categoryName: "Planning")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLauncher.shared.pendingAction = .planToday
        return .result()
    }
}

/// Bridges an intent that opens the app to a UI action once it's foreground.
@MainActor
final class IntentLauncher: ObservableObject {
    static let shared = IntentLauncher()
    enum Action: Equatable { case planToday }
    @Published var pendingAction: Action?
}

/// Registers the Siri phrases + Shortcuts tiles.
struct ChronosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TimeblockIntent(),
            phrases: [
                "Timeblock in \(.applicationName)",
                "Add a time block in \(.applicationName)",
                "Schedule time in \(.applicationName)",
            ],
            shortTitle: "New Time Block",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Add a reminder in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: PlanTodayIntent(),
            phrases: [
                "Plan today in \(.applicationName)",
                "Plan my day in \(.applicationName)",
            ],
            shortTitle: "Plan Today",
            systemImageName: "sunrise"
        )
    }
}

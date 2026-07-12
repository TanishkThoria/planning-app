import Foundation
import EventKit
import SwiftUI
import Combine

/// The single source of truth. Chronos deliberately has **no database of its
/// own** — every time block is a real `EKEvent` in Apple Calendar and every
/// task is a real `EKReminder` in Apple Reminders. This service loads
/// value-type snapshots for the UI, keeps the live EventKit objects cached
/// for mutation, and refreshes whenever the system store changes (edits made
/// in the Apple apps appear here automatically, and vice-versa).
@MainActor
final class EventKitService: ObservableObject {

    enum Access {
        case notDetermined, granted, denied
    }

    struct ServiceError: Identifiable {
        let id = UUID()
        let message: String
    }

    // MARK: Published state

    @Published private(set) var eventAccess: Access = .notDetermined
    @Published private(set) var reminderAccess: Access = .notDetermined

    /// Blocks inside the loaded window, sorted by start.
    @Published private(set) var blocks: [TimeBlock] = []
    /// Incomplete tasks plus tasks completed in the last 14 days.
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var taskLists: [CalendarInfo] = []
    @Published var lastError: ServiceError?

    let store = EKEventStore()

    // MARK: Private

    private var eventCache: [String: EKEvent] = [:]
    private var reminderCache: [String: EKReminder] = [:]
    private var window: DateInterval
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let today = Date().startOfDay
        window = DateInterval(start: today.adding(days: -45), end: today.adding(days: 90))
        readAuthorization()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    var hasFullAccess: Bool {
        eventAccess == .granted && reminderAccess == .granted
    }

    var wasDenied: Bool {
        eventAccess == .denied || reminderAccess == .denied
    }

    // MARK: - Authorization

    private func readAuthorization() {
        eventAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func map(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        default: return .denied
        }
    }

    func requestAccess() async {
        if eventAccess != .granted {
            do {
                let ok = try await store.requestFullAccessToEvents()
                eventAccess = ok ? .granted : .denied
            } catch {
                eventAccess = .denied
            }
        }
        if reminderAccess != .granted {
            do {
                let ok = try await store.requestFullAccessToReminders()
                reminderAccess = ok ? .granted : .denied
            } catch {
                reminderAccess = .denied
            }
        }
        refresh()
    }

    // MARK: - Loading

    /// Widens the loaded window when the user navigates near its edges.
    func ensureWindow(around date: Date) {
        let margin: TimeInterval = 14 * 86_400
        if date.timeIntervalSince(window.start) < margin || window.end.timeIntervalSince(date) < margin {
            let day = date.startOfDay
            window = DateInterval(start: day.adding(days: -45), end: day.adding(days: 90))
            refresh()
        }
    }

    func refresh() {
        guard eventAccess == .granted else { return }
        loadCalendars()
        loadEvents()
        if reminderAccess == .granted {
            Task { await loadReminders() }
        }
    }

    private func loadCalendars() {
        calendars = store.calendars(for: .event).map(snapshot(of:))
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        taskLists = store.calendars(for: .reminder).map(snapshot(of:))
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func snapshot(of calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: color(of: calendar),
            isEditable: calendar.allowsContentModifications,
            sourceTitle: calendar.source?.title ?? ""
        )
    }

    private func color(of calendar: EKCalendar) -> Color {
        #if os(macOS)
        return Color(nsColor: calendar.color)
        #else
        if let cg = calendar.cgColor { return Color(cgColor: cg) }
        return Theme.accentChoices[0].color
        #endif
    }

    private func loadEvents() {
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)

        var cache: [String: EKEvent] = [:]
        var snapshots: [TimeBlock] = []
        snapshots.reserveCapacity(events.count)

        for event in events {
            guard let block = snapshot(of: event) else { continue }
            cache[block.id] = event
            snapshots.append(block)
        }

        eventCache = cache
        blocks = snapshots.sorted { $0.start < $1.start }
    }

    private func snapshot(of event: EKEvent) -> TimeBlock? {
        guard let eventID = event.eventIdentifier,
              let start = event.startDate,
              let end = event.endDate,
              let calendar = event.calendar
        else { return nil }

        // Recurring occurrences share an eventIdentifier; suffix the start
        // time so each occurrence is individually addressable.
        let occurrenceID = "\(eventID)#\(Int(start.timeIntervalSinceReferenceDate))"

        var linkedTaskID: String?
        if let url = event.url, url.scheme == "chronos", url.host == "task" {
            let component = url.lastPathComponent
            if !component.isEmpty, component != "/" { linkedTaskID = component }
        }

        return TimeBlock(
            id: occurrenceID,
            eventID: eventID,
            title: event.title ?? "Untitled",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarID: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            color: color(of: calendar),
            notes: event.notes,
            location: event.location,
            linkedTaskID: linkedTaskID,
            hasRecurrence: event.hasRecurrenceRules,
            isEditable: calendar.allowsContentModifications
        )
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func loadReminders() async {
        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: Date().adding(days: -14), ending: nil, calendars: nil
        )
        let incomplete = await fetchReminders(matching: incompletePredicate)
        let completed = await fetchReminders(matching: completedPredicate)

        var cache: [String: EKReminder] = [:]
        var snapshots: [TaskItem] = []

        for reminder in incomplete + completed {
            guard let item = snapshot(of: reminder) else { continue }
            cache[item.id] = reminder
            snapshots.append(item)
        }

        reminderCache = cache
        tasks = snapshots.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?): return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private func snapshot(of reminder: EKReminder) -> TaskItem? {
        guard let list = reminder.calendar else { return nil }
        let comps = reminder.dueDateComponents
        let due = comps.flatMap { Calendar.current.date(from: $0) }

        return TaskItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            notes: TaskMetadata.strippingTokens(reminder.notes),
            dueDate: due,
            dueHasTime: comps?.hour != nil,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: .from(ekPriority: reminder.priority),
            listID: list.calendarIdentifier,
            listName: list.title,
            color: color(of: list),
            estimateMinutes: TaskMetadata.estimate(from: reminder.notes),
            sessionMinutes: TaskMetadata.session(from: reminder.notes),
            energy: TaskMetadata.energy(from: reminder.notes),
            parentID: TaskMetadata.parentID(from: reminder.notes)
        )
    }

    // MARK: - Lookup helpers

    func task(withID id: String) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    func calendarInfo(withID id: String?) -> CalendarInfo? {
        calendars.first { $0.id == id }
    }

    /// Blocks that occur (fully or partially) on the given day.
    func blocks(on day: Date, hiddenCalendars: Set<String> = []) -> [TimeBlock] {
        let dayStart = day.startOfDay
        let dayEnd = dayStart.adding(days: 1)
        return blocks.filter {
            !hiddenCalendars.contains($0.calendarID) && $0.start < dayEnd && $0.end > dayStart
        }
    }

    /// The occurrence ids of every block linked to the given task.
    func blocksLinked(to taskID: String) -> [TimeBlock] {
        blocks.filter { $0.linkedTaskID == taskID }
    }

    private func writableCalendar(for id: String?) -> EKCalendar? {
        if let id, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        return store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
    }

    private func writableList(for id: String?) -> EKCalendar? {
        if let id, let list = store.calendar(withIdentifier: id), list.allowsContentModifications {
            return list
        }
        return store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
    }

    private func fail(_ message: String, _ error: Error? = nil) {
        if let error {
            lastError = ServiceError(message: "\(message): \(error.localizedDescription)")
        } else {
            lastError = ServiceError(message: message)
        }
    }

    // MARK: - Block mutations

    static func taskLinkURL(for taskID: String) -> URL? {
        let encoded = taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskID
        return URL(string: "chronos://task/\(encoded)")
    }

    func createBlock(_ draft: BlockDraft) {
        guard let calendar = writableCalendar(for: draft.calendarID) else {
            fail("No writable calendar available")
            return
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft, to: event, isNew: true)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            refresh()
        } catch {
            fail("Couldn't create the block", error)
        }
    }

    func updateBlock(id: String, with draft: BlockDraft, span: EKSpan = .thisEvent) {
        guard let event = eventCache[id] else {
            fail("This block no longer exists — it may have been deleted in Calendar.")
            return
        }
        if let calendarID = draft.calendarID,
           calendarID != event.calendar?.calendarIdentifier,
           let calendar = writableCalendar(for: calendarID) {
            event.calendar = calendar
        }
        apply(draft, to: event, isNew: false)
        do {
            try store.save(event, span: span, commit: true)
            refresh()
        } catch {
            fail("Couldn't save the block", error)
        }
    }

    private func apply(_ draft: BlockDraft, to event: EKEvent, isNew: Bool) {
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled block"
            : draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.start
        event.endDate = draft.isAllDay ? max(draft.end, draft.start) : max(draft.end, draft.start.adding(minutes: 5))
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes

        if let taskID = draft.linkedTaskID {
            event.url = Self.taskLinkURL(for: taskID)
        } else if !draft.urlString.isEmpty {
            event.url = URL(string: draft.urlString)
        } else if isNew {
            event.url = nil
        } else if event.url?.scheme == "chronos" {
            // Editing removed the link.
            event.url = nil
        }

        // Only rewrite recurrence/alarms the user actually touched so
        // rules built in Apple Calendar survive round-trips.
        if isNew || draft.recurrence != draft.originalRecurrence {
            event.recurrenceRules = draft.recurrence.rule().map { [$0] }
        }
        if isNew || draft.alarm != draft.originalAlarm {
            event.alarms = draft.alarm.alarm().map { [$0] }
        }
    }

    /// Drag-to-move: shifts the occurrence keeping its duration.
    func moveBlock(id: String, to newStart: Date) {
        guard let event = eventCache[id], let start = event.startDate, let end = event.endDate else { return }
        let duration = end.timeIntervalSince(start)
        event.startDate = newStart
        event.endDate = newStart.addingTimeInterval(duration)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            refresh()
        } catch {
            fail("Couldn't move the block", error)
        }
    }

    /// Drag-to-resize: adjusts only the end.
    func resizeBlock(id: String, newEnd: Date) {
        guard let event = eventCache[id], let start = event.startDate else { return }
        event.endDate = max(newEnd, start.addingTimeInterval(5 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            refresh()
        } catch {
            fail("Couldn't resize the block", error)
        }
    }

    func deleteBlock(id: String, span: EKSpan = .thisEvent) {
        guard let event = eventCache[id] else { return }
        do {
            try store.remove(event, span: span, commit: true)
            refresh()
        } catch {
            fail("Couldn't delete the block", error)
        }
    }

    func duplicateBlock(id: String) {
        guard let source = eventCache[id],
              let start = source.startDate,
              let end = source.endDate,
              let calendar = source.calendar
        else { return }
        let copy = EKEvent(eventStore: store)
        copy.calendar = calendar
        copy.title = source.title
        copy.startDate = end
        copy.endDate = end.addingTimeInterval(end.timeIntervalSince(start))
        copy.notes = source.notes
        copy.location = source.location
        copy.isAllDay = source.isAllDay
        do {
            try store.save(copy, span: .thisEvent, commit: true)
            refresh()
        } catch {
            fail("Couldn't duplicate the block", error)
        }
    }

    /// Context-menu "Start now": pulls the block to the current moment.
    func startBlockNow(id: String, snap: Int) {
        moveBlock(id: id, to: Date().snappedDown(to: max(snap, 1)))
    }

    /// Editor context for an existing occurrence, reading live recurrence
    /// and alarm state from the underlying event.
    func editorContext(for block: TimeBlock) -> BlockEditorContext {
        let event = eventCache[block.id]
        let recurrence = RecurrenceOption.from(rules: event?.recurrenceRules)
        let alarm = AlarmOption.from(alarms: event?.alarms)
        var urlString = ""
        if let url = event?.url, url.scheme != "chronos" { urlString = url.absoluteString }

        var draft = BlockDraft()
        draft.title = block.title
        draft.calendarID = block.calendarID
        draft.start = block.start
        draft.end = block.end
        draft.isAllDay = block.isAllDay
        draft.location = block.location ?? ""
        draft.urlString = urlString
        draft.notes = block.notes ?? ""
        draft.recurrence = recurrence
        draft.alarm = alarm
        draft.linkedTaskID = block.linkedTaskID
        draft.originalRecurrence = recurrence
        draft.originalAlarm = alarm

        return BlockEditorContext(draft: draft, existingID: block.id, isRecurring: block.hasRecurrence)
    }

    // MARK: - Task mutations

    func createTask(_ draft: TaskDraft) {
        guard let list = writableList(for: draft.listID) else {
            fail("No writable reminder list available")
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        apply(draft, to: reminder)
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            fail("Couldn't create the task", error)
        }
    }

    func updateTask(id: String, with draft: TaskDraft) {
        guard let reminder = liveReminder(withID: id) else {
            fail("This task no longer exists — it may have been deleted in Reminders.")
            return
        }
        if let listID = draft.listID,
           listID != reminder.calendar?.calendarIdentifier,
           let list = writableList(for: listID) {
            reminder.calendar = list
        }
        apply(draft, to: reminder)
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            fail("Couldn't save the task", error)
        }
    }

    private func apply(_ draft: TaskDraft, to reminder: EKReminder) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.title = title.isEmpty ? "Untitled task" : title
        reminder.priority = draft.priority.rawValue
        reminder.notes = TaskMetadata.encode(
            notes: draft.notes,
            estimateMinutes: draft.estimateMinutes,
            sessionMinutes: draft.sessionMinutes,
            energy: draft.energy,
            parentID: draft.parentID
        )

        if draft.hasDue {
            var comps: Set<Calendar.Component> = [.year, .month, .day]
            if draft.hasTime { comps.formUnion([.hour, .minute]) }
            reminder.dueDateComponents = Calendar.current.dateComponents(comps, from: draft.due)
        } else {
            reminder.dueDateComponents = nil
        }

        if draft.isCompleted != reminder.isCompleted {
            reminder.isCompleted = draft.isCompleted
        }
    }

    func toggleTaskCompletion(id: String) {
        guard let reminder = liveReminder(withID: id) else { return }
        reminder.isCompleted = !reminder.isCompleted
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            fail("Couldn't update the task", error)
        }
    }

    func deleteTask(id: String) {
        guard let reminder = liveReminder(withID: id) else { return }
        do {
            // Cascade: subtasks would otherwise carry a dead parent link and
            // vanish from every nested view.
            for subtask in subtasks(of: id) {
                if let child = liveReminder(withID: subtask.id) {
                    try store.remove(child, commit: false)
                }
            }
            try store.remove(reminder, commit: true)
            refresh()
        } catch {
            fail("Couldn't delete the task", error)
        }
    }

    /// Cache lookup with a store fallback, so blocks linked to tasks
    /// outside the loaded set (e.g. completed long ago) still resolve.
    private func liveReminder(withID id: String) -> EKReminder? {
        reminderCache[id] ?? (store.calendarItem(withIdentifier: id) as? EKReminder)
    }

    func editorContext(for task: TaskItem) -> TaskEditorContext {
        var draft = TaskDraft()
        draft.title = task.title
        draft.listID = task.listID
        draft.hasDue = task.dueDate != nil
        draft.due = task.dueDate ?? Date().endOfDay
        draft.hasTime = task.dueHasTime
        draft.priority = task.priority
        draft.estimateMinutes = task.estimateMinutes
        draft.sessionMinutes = task.sessionMinutes
        draft.energy = task.energy
        draft.notes = task.notes ?? ""
        draft.isCompleted = task.isCompleted
        draft.parentID = task.parentID
        return TaskEditorContext(draft: draft, existingID: task.id)
    }

    // MARK: - Subtasks

    /// Chronos subtasks are real reminders carrying a `[sub:<parent-id>]`
    /// token, so they sync everywhere and can be timeblocked individually.
    func subtasks(of parentID: String) -> [TaskItem] {
        tasks.filter { $0.parentID == parentID }
    }

    func createSubtask(parentID: String, title: String, estimateMinutes: Int? = nil) {
        guard let parent = task(withID: parentID) else { return }
        var draft = TaskDraft()
        draft.title = title
        draft.listID = parent.listID
        draft.parentID = parentID
        draft.estimateMinutes = estimateMinutes
        if let due = parent.dueDate {
            draft.hasDue = true
            draft.due = due
            draft.hasTime = parent.dueHasTime
        }
        createTask(draft)
    }

    // MARK: - Timeblocking (the bridge between the two worlds)

    // MARK: - Day templates

    /// Snapshots a day's timed blocks into reusable template blocks.
    func templateBlocks(for day: Date) -> [TemplateBlock] {
        blocks(on: day)
            .filter { !$0.isAllDay }
            .compactMap { block in
                guard let clamped = block.clamped(to: day) else { return nil }
                return TemplateBlock(
                    title: block.title,
                    startMinutes: clamped.start.minutesSinceMidnight,
                    durationMinutes: max(5, Int(clamped.end.timeIntervalSince(clamped.start) / 60)),
                    calendarID: block.calendarID
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Stamps a template's blocks onto `day`, committing once.
    func applyTemplate(_ template: DayTemplate, to day: Date, fallbackCalendarID: String?) {
        var created = 0
        for tb in template.blocks {
            guard let calendar = writableCalendar(for: tb.calendarID ?? fallbackCalendarID) else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = tb.title
            event.startDate = day.at(minutes: tb.startMinutes)
            event.endDate = day.at(minutes: tb.startMinutes + max(tb.durationMinutes, 5))
            do {
                try store.save(event, span: .thisEvent, commit: false)
                created += 1
            } catch {
                continue
            }
        }
        guard created > 0 else { return }
        do {
            try store.commit()
            refresh()
        } catch {
            fail("Couldn't apply the template", error)
        }
    }

    /// Creates a calendar event for a reminder and links the two. The link
    /// travels inside the event's URL so it syncs everywhere EventKit does.
    func scheduleTask(_ task: TaskItem, at start: Date, minutes: Int, calendarID: String?) {
        guard let calendar = writableCalendar(for: calendarID) else {
            fail("No writable calendar available")
            return
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = task.title
        event.startDate = start
        event.endDate = start.adding(minutes: max(minutes, 5))
        event.url = Self.taskLinkURL(for: task.id)
        if let notes = task.notes, !notes.isEmpty { event.notes = notes }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            refresh()
        } catch {
            fail("Couldn't schedule the task", error)
        }
    }
}

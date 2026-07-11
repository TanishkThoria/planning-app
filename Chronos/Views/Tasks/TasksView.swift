import SwiftUI

/// Full task manager over Apple Reminders: filters, search, instant
/// natural-language entry, and one-tap scheduling into the calendar.
struct TasksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    @AppStorage(Prefs.defaultListID) private var defaultListID = ""
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30

    enum Filter: String, CaseIterable, Identifiable {
        case today = "Today"
        case upcoming = "Upcoming"
        case anytime = "Anytime"
        case done = "Done"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .today
    @State private var searchText = ""
    @State private var quickEntry = ""
    @FocusState private var entryFocused: Bool

    private var visibleTasks: [TaskItem] {
        service.tasks.filter { !model.hiddenListIDs.contains($0.listID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)

            quickEntryField
                .padding(.horizontal, 18)
                .padding(.top, 12)

            filterBar
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                    let groups = sections()
                    if groups.allSatisfy({ $0.tasks.isEmpty }) {
                        EmptyStateView(
                            icon: filter == .done ? "moon.zzz" : "checkmark.circle",
                            title: filter == .done ? "Nothing finished yet" : "All clear",
                            message: emptyMessage
                        )
                    } else {
                        ForEach(groups, id: \.title) { group in
                            if !group.tasks.isEmpty {
                                SectionHeader(title: group.title, trailing: "\(group.tasks.count)")
                                    .padding(.top, 12)
                                    .padding(.horizontal, 4)
                                ForEach(group.tasks) { task in
                                    TaskRow(task: task)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var emptyMessage: String {
        switch filter {
        case .today: return "No tasks due today. Enjoy the slack or pull something forward from Upcoming."
        case .upcoming: return "Nothing on the horizon for the next few weeks."
        case .anytime: return "No unscheduled, undated tasks."
        case .done: return "Completed tasks from the last two weeks will show up here."
        }
    }

    // MARK: Header & entry

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                let open = visibleTasks.filter { !$0.isCompleted }.count
                Text("\(open) open · synced with Apple Reminders")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "plus", prominent: true) {
                model.newTask(listID: defaultListID.isEmpty ? nil : defaultListID)
            }
        }
    }

    private var quickEntryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            TextField("Add a task — try \u{201C}Send invoice friday 5pm !! ~30m\u{201D}", text: $quickEntry)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .focused($entryFocused)
                .onSubmit(submitQuickEntry)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(entryFocused ? Color.accentColor.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
    }

    private func submitQuickEntry() {
        let text = quickEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parsed = QuickAddParser.parse(text, defaultDurationMinutes: defaultBlockMinutes)
        guard parsed.isValid else { return }

        var draft = TaskDraft()
        draft.title = parsed.title
        draft.listID = defaultListID.isEmpty ? nil : defaultListID
        draft.priority = parsed.priority
        draft.estimateMinutes = parsed.estimateMinutes
        if let date = parsed.date {
            draft.hasDue = true
            draft.due = date
            draft.hasTime = parsed.hasExplicitTime
        }
        service.createTask(draft)
        quickEntry = ""
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(filter == item ? Theme.bg : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            filter == item ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(maxWidth: 140)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.fill, in: Capsule())
        }
    }

    // MARK: Sectioning

    private struct Group2 {
        let title: String
        let tasks: [TaskItem]
    }

    private func sections() -> [Group2] {
        var tasks = visibleTasks
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            tasks = tasks.filter {
                $0.title.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false)
            }
        }

        let today = Date().startOfDay
        switch filter {
        case .today:
            let open = tasks.filter { !$0.isCompleted }
            let overdue = open.filter { ($0.dueDate?.startOfDay ?? .distantFuture) < today }
            let dueToday = open.filter { $0.dueDate?.isToday == true }
            let flagged = open.filter { $0.dueDate == nil && $0.priority == .high }
            return [
                Group2(title: "Overdue", tasks: overdue),
                Group2(title: "Today", tasks: dueToday),
                Group2(title: "High Priority", tasks: flagged),
            ]
        case .upcoming:
            let open = tasks.filter { !$0.isCompleted }
            let upcoming = open
                .filter { ($0.dueDate?.startOfDay ?? .distantPast) > today }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            let byDay = Dictionary(grouping: upcoming) { $0.dueDate?.startOfDay ?? today }
            return byDay.keys.sorted().map { day in
                Group2(title: Fmt.relativeDay(day), tasks: byDay[day] ?? [])
            }
        case .anytime:
            let open = tasks.filter { !$0.isCompleted && $0.dueDate == nil }
            let byList = Dictionary(grouping: open, by: \.listName)
            return byList.keys.sorted().map { list in
                Group2(title: list, tasks: byList[list] ?? [])
            }
        case .done:
            let done = tasks.filter(\.isCompleted)
                .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
            return [Group2(title: "Completed", tasks: done)]
        }
    }
}

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

    enum Mode: String, CaseIterable, Identifiable {
        case list = "List"
        case matrix = "Matrix"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .list
    @State private var selectionMode = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.top, 10)

            if mode == .matrix {
                MatrixView(embedded: true)
            } else {
                listContent
            }
        }
        .background(Theme.bg)
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            quickEntryField
                .padding(.horizontal, 18)
                .padding(.top, 12)

            filterBar
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                    if filter != .done {
                        CrunchRadar()
                            .padding(.top, 12)
                    }
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
                                    TaskRow(
                                        task: task,
                                        selectionMode: selectionMode,
                                        isSelected: selected.contains(task.id),
                                        onToggleSelection: { toggleSelection(task.id) }
                                    )
                                    // Open subtasks ride along under their parent.
                                    if !selectionMode {
                                        ForEach(service.subtasks(of: task.id).filter { !$0.isCompleted }) { subtask in
                                            SubtaskRow(task: subtask)
                                                .padding(.leading, 28)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            if selectionMode && !selected.isEmpty {
                bulkActionBar
            }
        }
        .background(Theme.bg)
    }

    // MARK: Bulk selection

    private func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        Haptics.selection()
    }

    private var selectedTasks: [TaskItem] {
        visibleTasks.filter { selected.contains($0.id) }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 4) {
            bulkButton("Done", "checkmark.circle") {
                for id in selected where service.task(withID: id)?.isCompleted == false {
                    service.toggleTaskCompletion(id: id)
                }
                Haptics.success(); exitSelection()
            }
            Menu {
                ForEach(TaskPriority.allCases) { p in
                    Button(p.label) { applyPriority(p) }
                }
            } label: { bulkLabel("Priority", "exclamationmark.circle") }

            Menu {
                ForEach(service.taskLists.filter(\.isEditable)) { list in
                    Button(list.title) { moveToList(list.id) }
                }
            } label: { bulkLabel("List", "tray.and.arrow.down") }

            bulkButton("Delete", "trash", tint: Theme.danger) {
                for id in selected { service.deleteTask(id: id) }
                exitSelection()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func bulkButton(_ label: String, _ icon: String, tint: Color = Theme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) { bulkLabel(label, icon, tint: tint) }.buttonStyle(.plain)
    }

    private func bulkLabel(_ label: String, _ icon: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 15))
            Text("\(label)").font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func applyPriority(_ priority: TaskPriority) {
        for task in selectedTasks {
            var ctx = service.editorContext(for: task)
            ctx.draft.priority = priority
            if let id = ctx.existingID { service.updateTask(id: id, with: ctx.draft) }
        }
        Haptics.success(); exitSelection()
    }

    private func moveToList(_ listID: String) {
        for task in selectedTasks {
            var ctx = service.editorContext(for: task)
            ctx.draft.listID = listID
            if let id = ctx.existingID { service.updateTask(id: id, with: ctx.draft) }
        }
        Haptics.success(); exitSelection()
    }

    private func exitSelection() {
        selected.removeAll()
        selectionMode = false
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
            OverflowMenu {
                if mode == .list {
                    Button {
                        selectionMode.toggle()
                        if !selectionMode { selected.removeAll() }
                    } label: {
                        Label(selectionMode ? "Done selecting" : "Select multiple",
                              systemImage: selectionMode ? "checkmark.circle.fill" : "checklist")
                    }
                }
                Button { model.deadlinePlanPresented = true } label: {
                    Label("Plan Deadlines — study before due dates", systemImage: "calendar.badge.clock")
                }
                if visibleTasks.contains(where: { $0.isOverdue }) {
                    Button { model.overdueSweepPresented = true } label: {
                        Label("Sweep Overdue into open time", systemImage: "calendar.badge.exclamationmark")
                    }
                }
            }
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
        VStack(spacing: 8) {
            // Chips never compress or wrap — they scroll if space runs out.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases) { item in
                        Button {
                            filter = item
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
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
                }
                .padding(.trailing, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search tasks", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.fill, in: Capsule())
        }
    }

    // MARK: Sectioning

    private struct Group2 {
        let title: String
        let tasks: [TaskItem]
    }

    /// True only when the task nests under a parent that is still visible
    /// (exists and is open) — the only case where it's hidden from
    /// top-level lists.
    private func hasOpenParent(_ task: TaskItem) -> Bool {
        guard let parentID = task.parentID,
              let parent = service.task(withID: parentID) else { return false }
        return !parent.isCompleted
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
            // Top-level only; subtasks render nested under their parent.
            // Orphaned subtasks (parent deleted/completed) surface as
            // top-level so they can never silently disappear.
            let open = tasks.filter { !$0.isCompleted && !hasOpenParent($0) }
            let overdue = open.filter { ($0.dueDate?.startOfDay ?? .distantFuture) < today }
            let dueToday = open.filter { $0.dueDate?.isToday == true }
            let flagged = open.filter { $0.dueDate == nil && $0.priority == .high }
            return [
                Group2(title: "Overdue", tasks: overdue),
                Group2(title: "Today", tasks: dueToday),
                Group2(title: "High Priority", tasks: flagged),
            ]
        case .upcoming:
            let open = tasks.filter { !$0.isCompleted && !hasOpenParent($0) }
            let upcoming = open
                .filter { ($0.dueDate?.startOfDay ?? .distantPast) > today }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            let byDay = Dictionary(grouping: upcoming) { $0.dueDate?.startOfDay ?? today }
            return byDay.keys.sorted().map { day in
                Group2(title: Fmt.relativeDay(day), tasks: byDay[day] ?? [])
            }
        case .anytime:
            let open = tasks.filter { !$0.isCompleted && $0.dueDate == nil && !hasOpenParent($0) }
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

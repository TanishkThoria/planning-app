import SwiftUI

/// Global search across everything — every event and task, by title, notes,
/// or location — with instant results you can jump straight into. The fast
/// way to find "that thing" without remembering which day it's on.
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var blockResults: [TimeBlock] {
        guard trimmed.count >= 2 else { return [] }
        return service.blocks
            .filter { matches($0.title, $0.notes, $0.location) }
            .sorted { distance($0.start) < distance($1.start) }
            .prefix(25).map { $0 }
    }

    private var taskResults: [TaskItem] {
        guard trimmed.count >= 2 else { return [] }
        return service.tasks
            .filter { matches($0.title, $0.notes, nil) }
            .sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
            .prefix(25).map { $0 }
    }

    private func matches(_ fields: String?...) -> Bool {
        fields.contains { ($0 ?? "").lowercased().contains(trimmed) }
    }

    /// Closeness to now, so the most relevant dates float up.
    private func distance(_ date: Date) -> TimeInterval { abs(date.timeIntervalSinceNow) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
        }
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 520, height: 600)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            TextField("Search events and tasks", text: $query)
                .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                .focused($focused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if trimmed.count < 2 {
            EmptyStateView(icon: "magnifyingglass", title: "Search everything",
                           message: "Find any event or task by name, note, or location.")
            Spacer()
        } else if blockResults.isEmpty && taskResults.isEmpty {
            EmptyStateView(icon: "questionmark.circle", title: "No matches",
                           message: "Nothing found for “\(query)”. Try a different term.")
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !taskResults.isEmpty {
                        SectionHeader(title: "Tasks", trailing: "\(taskResults.count)")
                            .padding(.horizontal, 4).padding(.top, 8)
                        ForEach(taskResults) { task in taskRow(task) }
                    }
                    if !blockResults.isEmpty {
                        SectionHeader(title: "Events", trailing: "\(blockResults.count)")
                            .padding(.horizontal, 4).padding(.top, 12)
                        ForEach(blockResults) { block in blockRow(block) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        Button {
            model.taskEditor = service.editorContext(for: task)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(task.isCompleted ? Theme.success : task.priority.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    HStack(spacing: 6) {
                        if let due = task.dueLabel() {
                            Text(due).font(.system(size: 10, design: .rounded))
                                .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                        }
                        Text(task.listName).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func blockRow(_ block: TimeBlock) -> some View {
        Button {
            model.blockEditor = service.editorContext(for: block)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(block.color).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(block.isAllDay
                         ? "\(Fmt.relativeDay(block.start)) · all-day"
                         : "\(Fmt.relativeDay(block.start)) · \(Fmt.timeRange(block.start, block.end))")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

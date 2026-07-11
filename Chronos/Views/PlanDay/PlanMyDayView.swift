import SwiftUI

/// One-tap daily planning: pick the tasks that matter, Chronos fits them
/// into the free gaps of your working hours, you confirm, and real calendar
/// events (linked back to their reminders) are created.
struct PlanMyDayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var included: Set<String> = []
    @State private var initialized = false

    private var day: Date { model.selectedDate }

    /// Candidates: open tasks with no block on this day already —
    /// overdue and due-today first, undated ones after.
    private var candidates: [TaskItem] {
        let scheduled = Set(service.blocks(on: day).compactMap(\.linkedTaskID))
        return service.tasks
            .filter { task in
                guard !task.isCompleted, !scheduled.contains(task.id),
                      !model.hiddenListIDs.contains(task.listID) else { return false }
                guard let due = task.dueDate else { return true }
                return due.startOfDay <= day.startOfDay
            }
            .sorted { a, b in
                let aDated = a.dueDate != nil, bDated = b.dueDate != nil
                if aDated != bDated { return aDated }
                if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    private var proposals: [AutoScheduler.Proposal] {
        AutoScheduler.plan(
            tasks: candidates.filter { included.contains($0.id) },
            existing: service.blocks(on: day),
            on: day,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            defaultMinutes: defaultBlockMinutes,
            gapPaddingMinutes: gapMinutes
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Theme.hairline).frame(height: 1)

            if candidates.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "Nothing to plan",
                    message: "Every open task for \(Fmt.relativeDay(day).lowercased()) is already on the timeline."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(candidates) { task in
                            candidateRow(task)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 480, height: 560)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear {
            guard !initialized else { return }
            initialized = true
            // Dated (due/overdue) tasks are in by default; undated ones opt-in.
            included = Set(candidates.filter { $0.dueDate != nil }.map(\.id))
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 1) {
                Text("Plan My Day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            // Symmetry spacer so the title stays centered.
            Text("Cancel").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func candidateRow(_ task: TaskItem) -> some View {
        let proposal = proposals.first { $0.task.id == task.id }
        let isIncluded = included.contains(task.id)

        return Button {
            if isIncluded { included.remove(task.id) } else { included.insert(task.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isIncluded ? Color.accentColor : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("~\(Fmt.duration(minutes: task.estimateMinutes ?? defaultBlockMinutes))")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                        if task.isOverdue {
                            Text("overdue")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.danger)
                        }
                        if task.priority != .none {
                            Text(task.priority.badge)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(task.priority.color)
                        }
                    }
                }

                Spacer()

                if isIncluded {
                    if let proposal {
                        Text(Fmt.timeRange(proposal.start, proposal.end))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("no room")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            let unplaced = included.count - proposals.count
            VStack(alignment: .leading, spacing: 1) {
                Text("\(proposals.count) block\(proposals.count == 1 ? "" : "s") will be created")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if unplaced > 0 {
                    Text("\(unplaced) didn't fit — free up time or shorten estimates")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Button {
                apply()
            } label: {
                Text("Add to Calendar")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(proposals.isEmpty)
            .opacity(proposals.isEmpty ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func apply() {
        for proposal in proposals {
            service.scheduleTask(
                proposal.task,
                at: proposal.start,
                minutes: proposal.minutes,
                calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
            )
        }
        dismiss()
    }
}

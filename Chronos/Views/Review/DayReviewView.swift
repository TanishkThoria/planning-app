import SwiftUI

/// End-of-day review, and the destination for post-block check-in nudges.
/// Walks the day's finished task-linked blocks and asks what happened:
/// did you do it, does it need more time, did it slip? Each answer writes
/// back to Reminders/Calendar and, where useful, reschedules into your next
/// free slot (profile-aware).
struct DayReviewView: View {
    let day: Date

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    /// Blocks the user has acted on this session, so they drop out.
    @State private var handled: Set<String> = []

    /// Past, timed, task-linked blocks whose task is still open — the ones
    /// that need a decision.
    private var pending: [ReviewItem] {
        service.blocks(on: day)
            .filter { block in
                guard !block.isAllDay, block.end < Date(), let taskID = block.linkedTaskID,
                      !handled.contains(block.id) else { return false }
                return service.task(withID: taskID)?.isCompleted == false
            }
            .sorted { $0.start < $1.start }
            .compactMap { block in
                service.task(withID: block.linkedTaskID ?? "").map { ReviewItem(block: block, task: $0) }
            }
    }

    private var completedToday: Int {
        service.tasks.filter { $0.isCompleted && ($0.completionDate?.isSameDay(as: day) ?? false) }.count
    }

    struct ReviewItem: Identifiable {
        let block: TimeBlock
        let task: TaskItem
        var id: String { block.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard

                    if pending.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.seal.fill",
                            title: "All caught up",
                            message: "Every finished block has been reviewed. Nice work closing the loop."
                        )
                    } else {
                        SectionHeader(title: "Needs a decision", trailing: "\(pending.count)")
                        ForEach(pending) { item in
                            reviewCard(item)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 480, height: 600)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var headerBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            VStack(spacing: 1) {
                Text("Review")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("Close").font(.system(size: 14.5)).hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryCard: some View {
        let dayBlocks = service.blocks(on: day).filter { !$0.isAllDay }
        let planned = dayBlocks.compactMap { $0.clamped(to: day) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        return HStack(spacing: 0) {
            summaryMetric("\(dayBlocks.count)", "blocks")
            divider
            summaryMetric(Fmt.duration(minutes: planned), "planned")
            divider
            summaryMetric("\(completedToday)", "done")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 30)
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewCard(_ item: ReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(item.block.color).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.task.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(Fmt.timeRange(item.block.start, item.block.end))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }

            // Decision buttons
            HStack(spacing: 6) {
                reviewAction("Did it", "checkmark", tint: Theme.success) {
                    service.toggleTaskCompletion(id: item.task.id)
                    handled.insert(item.block.id)
                }
                reviewAction("More time", "plus.circle", tint: Theme.accentColor) {
                    scheduleFollowUp(item, extend: true)
                }
                reviewAction("Reschedule", "arrow.uturn.forward", tint: Theme.warning) {
                    reschedule(item)
                }
                reviewAction("Skip", "xmark", tint: Theme.textTertiary) {
                    handled.insert(item.block.id)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reviewAction(_ label: String, _ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(pending.isEmpty ? "Review complete" : "\(pending.count) left to review")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: Actions

    /// Adds another block for the task at the next free slot (needs-more-time).
    private func scheduleFollowUp(_ item: ReviewItem, extend: Bool) {
        let minutes = item.task.estimateMinutes ?? item.block.durationMinutes
        let start = AutoScheduler.nextFreeSlot(
            after: Date(),
            minutes: minutes,
            existing: service.blocks,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            profile: profileStore.profile
        )
        service.scheduleTask(
            item.task,
            at: start,
            minutes: minutes,
            calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
        )
        handled.insert(item.block.id)
    }

    /// Moves the slipped block forward to the next free slot.
    private func reschedule(_ item: ReviewItem) {
        let minutes = item.block.durationMinutes
        let start = AutoScheduler.nextFreeSlot(
            after: Date(),
            minutes: minutes,
            existing: service.blocks.filter { $0.id != item.block.id },
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            profile: profileStore.profile
        )
        service.moveBlock(id: item.block.id, to: start)
        handled.insert(item.block.id)
    }
}

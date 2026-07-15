import SwiftUI

/// Adaptive rescheduling. When the day gets away from you, Reflow sweeps up
/// every block that slipped — a task-linked block whose time has passed but
/// whose task isn't done — and slots each one into the next free stretch of
/// your day (profile-aware), sequentially so they never collide. You see the
/// whole move list and confirm. The antidote to a broken plan.
struct ReflowView: View {
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @State private var now = Date()

    /// Past, task-linked blocks on today whose task is still open.
    private var slippedBlocks: [TimeBlock] {
        service.blocks(on: now)
            .filter { block in
                guard !block.isAllDay, block.end < now, let id = block.linkedTaskID else { return false }
                return service.task(withID: id)?.isCompleted == false
            }
            .sorted { $0.start < $1.start }
    }

    struct Move: Identifiable {
        let block: TimeBlock
        let newStart: Date
        var id: String { block.id }
        var newEnd: Date { newStart.adding(minutes: block.durationMinutes) }
    }

    /// Sequentially finds the next free slot for each slipped block, treating
    /// earlier moves as busy so nothing double-books.
    private var moves: [Move] {
        var existing = service.blocks
        var result: [Move] = []
        for block in slippedBlocks {
            let minutes = max(block.durationMinutes, 5)
            let start = AutoScheduler.nextFreeSlot(
                after: now,
                minutes: minutes,
                existing: existing.filter { $0.id != block.id },
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                snapMinutes: snapMinutes,
                profile: profileStore.profile
            )
            result.append(Move(block: block, newStart: start))
            // Reserve the new slot for subsequent placements.
            var moved = block
            moved = TimeBlock(
                id: block.id, eventID: block.eventID, title: block.title,
                start: start, end: start.adding(minutes: minutes), isAllDay: false,
                calendarID: block.calendarID, calendarTitle: block.calendarTitle,
                color: block.color, notes: nil, location: nil,
                linkedTaskID: block.linkedTaskID, hasRecurrence: false, isEditable: true
            )
            existing = existing.filter { $0.id != block.id } + [moved]
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if slippedBlocks.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing slipped",
                    message: "Every block so far today is either done or still ahead. You're on track."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("These blocks passed without their task getting done. Here's where they'd move:")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                            .padding(.bottom, 4)
                        ForEach(moves) { move in
                            moveRow(move)
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
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { now = Date() }
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 1) {
                Text("Reflow Day").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(slippedBlocks.count) slipped").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("Cancel").font(.system(size: 14.5)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func moveRow(_ move: Move) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(move.block.color).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.block.title)
                    .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(Fmt.timeRange(move.block.start, move.block.end))
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        .strikethrough(color: Theme.textTertiary)
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    Text(Fmt.timeRange(move.newStart, move.newEnd))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentColor)
                }
            }
            Spacer()
            Text(Fmt.relativeDay(move.newStart))
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Text(moves.isEmpty ? "" : "\(moves.count) block\(moves.count == 1 ? "" : "s") will move")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                apply()
            } label: {
                Text("Reflow")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(moves.isEmpty)
            .opacity(moves.isEmpty ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func apply() {
        let snapshot = moves
        for move in snapshot {
            service.moveBlock(id: move.block.id, to: move.newStart)
        }
        Haptics.success()
        dismiss()
    }
}

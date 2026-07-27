import SwiftUI

/// Distraction-free "Now" mode. One screen, one thing: what you're doing right
/// this minute, a live countdown, and a single next action. Everything else —
/// the lists, the badges, the noise — disappears. Built for the overwhelmed
/// and the easily-distracted: when the whole app is too much, this is enough.
struct NowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var timer: FocusTimerController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""
    @AppStorage(Prefs.accentName) private var accentName = "Blue"

    @State private var now = Date()
    @State private var parked = ""
    @State private var parkedOK = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var todayBlocks: [TimeBlock] {
        service.blocks(on: Date().startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
    }
    private var current: TimeBlock? { todayBlocks.first { $0.start <= now && now < $0.end } }
    private var next: TimeBlock? { todayBlocks.first { $0.start > now } }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                centerpiece
                Spacer()
                upNext
                parkField
            }
            .padding(24)
        }
        .chronosAppearance()
        .tint(Theme.accent(named: accentName))
        .onReceive(tick) { now = $0 }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private var topBar: some View {
        HStack {
            Text("NOW")
                .font(.system(size: 13.5, weight: .bold)).tracking(3)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var centerpiece: some View {
        if let block = current {
            VStack(spacing: 20) {
                Text("RIGHT NOW")
                    .font(.system(size: 12.5, weight: .bold)).tracking(2)
                    .foregroundStyle(Theme.accentColor)
                Text(block.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)

                Text(countdown(to: block.end) + " left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()

                progressBar(from: block.start, to: block.end)

                HStack(spacing: 12) {
                    if let url = block.meetingURL {
                        Link(destination: url) {
                            actionPill("Join", "video.fill", filled: true)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        model.startFocus(taskID: block.linkedTaskID, title: block.title)
                    } label: {
                        actionPill("Focus", "timer", filled: block.meetingURL == nil)
                    }
                    .buttonStyle(.plain)
                    if let taskID = block.linkedTaskID, let task = service.task(withID: taskID), !task.isCompleted {
                        Button {
                            Haptics.success()
                            service.toggleTaskCompletion(id: taskID)
                        } label: {
                            actionPill("Done", "checkmark", filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if let block = next {
            VStack(spacing: 18) {
                Text("UP NEXT IN \(countdown(to: block.start))")
                    .font(.system(size: 13.5, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                Text(block.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.6)
                Text("at \(Fmt.time.string(from: block.start))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("You've got a moment. Breathe, or get a head start.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        } else {
            openState
        }
    }

    private var openState: some View {
        VStack(spacing: 16) {
            Text("🌿").font(.system(size: 44))
            Text("Nothing scheduled right now")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let frog = model.frogTaskID.flatMap({ service.task(withID: $0) }), !frog.isCompleted {
                VStack(spacing: 10) {
                    Text("Your one important thing:")
                        .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textTertiary)
                    Text("🐸 \(frog.title)")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Button {
                        timer.focusMinutes = 5
                        timer.start(taskID: frog.id, title: frog.title, mode: .pomodoro)
                        model.startFocus(taskID: frog.id, title: frog.title)
                    } label: {
                        actionPill("Just start · 5 min", "bolt.fill", filled: true)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { dismiss(); model.afterDismiss { model.planDayPresented = true } } label: {
                    actionPill("Plan my day", "wand.and.stars", filled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var upNext: some View {
        if current != nil, let block = next {
            HStack(spacing: 8) {
                Text("NEXT")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.textTertiary)
                Text(block.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(Fmt.time.string(from: block.start))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.top, 8)
        }
    }

    private var parkField: some View {
        HStack(spacing: 8) {
            Image(systemName: parkedOK ? "checkmark.circle.fill" : "tray.and.arrow.down")
                .font(.system(size: 14.5))
                .foregroundStyle(parkedOK ? Theme.success : Theme.textTertiary)
            TextField("Park a thought…", text: $parked)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
                .submitLabel(.done)
                .onSubmit(park)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.top, 10)
    }

    // MARK: Bits

    private func actionPill(_ title: String, _ icon: String, filled: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? Theme.bg : Theme.accentColor)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(filled ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.accentColor.opacity(0.14)),
                        in: Capsule())
    }

    private func progressBar(from start: Date, to end: Date) -> some View {
        let total = max(end.timeIntervalSince(start), 1)
        let done = min(max(now.timeIntervalSince(start), 0), total)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(Theme.accentColor)
                    .frame(width: geo.size.width * (done / total))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 240)
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func park() {
        let trimmed = parked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var draft = TaskDraft()
        draft.title = trimmed
        draft.listID = defaultListID.isEmpty ? nil : defaultListID
        service.createTask(draft)
        parked = ""
        Haptics.success()
        withAnimation(.snappy) { parkedOK = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.snappy) { parkedOK = false }
        }
    }
}

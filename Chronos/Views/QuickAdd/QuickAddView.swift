import SwiftUI

/// ⌘K command bar: type naturally, watch the live interpretation, hit
/// return. Creates a calendar block or a reminder without touching a form.
struct QuickAddView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""

    enum KindOverride: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case block = "Block"
        case task = "Task"
        var id: String { rawValue }
    }

    @State private var text = ""
    @State private var kindOverride: KindOverride = .auto
    @FocusState private var focused: Bool

    private var parsed: QuickAddParser.Result {
        var result = QuickAddParser.parse(text, defaultDurationMinutes: defaultBlockMinutes)
        switch kindOverride {
        case .auto: break
        case .block: result.kind = .block
        case .task: result.kind = .task
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                TextField("Deep work 9-11am · Standup tmr 9:15 15m · todo Ship it fri !!", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .onSubmit(submit)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
            )

            HStack {
                Picker("", selection: $kindOverride) {
                    ForEach(KindOverride.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)

                Spacer()

                Button(action: submit) {
                    Text("Create")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!parsed.isValid)
                .opacity(parsed.isValid ? 1 : 0.4)
            }

            if parsed.isValid {
                previewCard
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SYNTAX")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Times: 9-11am, 3pm, 14:30 · Days: today, tmr, fri, next mon · Length: 45m, 1.5h")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text("Tasks: start with \u{201C}todo\u{201D} or \u{201C}t\u{201D} · Priority: ! !! !!! · Estimate: ~30m")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 520, height: 320)
        #else
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { focused = true }
    }

    private var previewCard: some View {
        HStack(spacing: 10) {
            Image(systemName: parsed.kind == .block ? "rectangle.stack.fill" : "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(parsed.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(previewDetail)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewDetail: String {
        if parsed.kind == .task {
            var parts = ["Reminder"]
            if let date = parsed.date {
                parts.append(parsed.hasExplicitTime
                    ? "due \(Fmt.relativeDay(date)) \(Fmt.time.string(from: date))"
                    : "due \(Fmt.relativeDay(date))")
            }
            if parsed.priority != .none { parts.append("\(parsed.priority.label.lowercased()) priority") }
            if let est = parsed.estimateMinutes { parts.append("~\(Fmt.duration(minutes: est))") }
            return parts.joined(separator: " · ")
        } else {
            let start = blockStart
            let minutes = parsed.durationMinutes ?? defaultBlockMinutes
            let suffix = parsed.hasExplicitTime ? "" : " (next free slot)"
            return "\(Fmt.relativeDay(start)) \(Fmt.timeRange(start, start.adding(minutes: minutes)))\(suffix)"
        }
    }

    /// Explicit time wins; otherwise the next free slot on the target day.
    private var blockStart: Date {
        if parsed.hasExplicitTime, let date = parsed.date { return date }
        let minutes = parsed.durationMinutes ?? defaultBlockMinutes
        let baseDay = parsed.date ?? model.selectedDate
        let from = baseDay.isToday ? Date() : baseDay.at(minutes: workStartMinutes)
        return AutoScheduler.nextFreeSlot(
            after: max(from, Date()),
            minutes: minutes,
            existing: service.blocks,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes
        )
    }

    private func submit() {
        guard parsed.isValid else { return }

        if parsed.kind == .task {
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
        } else {
            var draft = BlockDraft()
            draft.title = parsed.title
            draft.calendarID = defaultCalendarID.isEmpty ? nil : defaultCalendarID
            draft.start = blockStart
            draft.end = draft.start.adding(minutes: parsed.durationMinutes ?? defaultBlockMinutes)
            service.createBlock(draft)
        }
        dismiss()
    }
}

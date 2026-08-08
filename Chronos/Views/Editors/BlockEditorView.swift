import SwiftUI
import EventKit

struct BlockEditorView: View {
    let context: BlockEditorContext

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var draft: BlockDraft
    @State private var applyToFuture = false
    @State private var confirmingDelete = false

    private var isNew: Bool { context.existingID == nil }

    init(context: BlockEditorContext) {
        self.context = context
        var draft = context.draft
        if draft.calendarID == nil {
            draft.calendarID = UserDefaults.standard.string(forKey: Prefs.defaultCalendarID)
        }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        EditorSheet(
            title: isNew ? "New Block" : "Edit Block",
            confirmDisabled: draft.title.trimmingCharacters(in: .whitespaces).isEmpty && isNew,
            onConfirm: save
        ) {
            TitleField(placeholder: "Block title", text: $draft.title)

            if let taskID = draft.linkedTaskID, let task = service.task(withID: taskID) {
                linkedTaskBanner(task)
            }

            VStack(spacing: 6) {
                CalendarPickerRow(label: "Calendar", options: service.calendars, selection: $draft.calendarID, icon: "calendar")

                CategoryField(title: draft.title, override: $draft.categoryOverride)

                colorRow

                FieldRow(label: "All-day", icon: "sun.max") {
                    Toggle("", isOn: $draft.isAllDay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                FieldRow(label: "Date", icon: "calendar") {
                    DatePicker("", selection: $draft.start, displayedComponents: [.date])
                        .labelsHidden()
                }

                if !draft.isAllDay {
                    FieldRow(label: "Starts", icon: "clock") {
                        DatePicker("", selection: $draft.start, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }
                    FieldRow(label: "Ends", icon: "clock.badge.checkmark") {
                        DatePicker(
                            "",
                            selection: $draft.end,
                            in: draft.start.adding(minutes: 5)...,
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                    }
                    HStack {
                        Spacer()
                        DurationChips(current: draft.durationMinutes) { minutes in
                            draft.end = draft.start.adding(minutes: minutes)
                        }
                    }
                }
            }
            .onChange(of: draft.start) { oldValue, newValue in
                // Moving the start keeps the duration.
                draft.end = draft.end.addingTimeInterval(newValue.timeIntervalSince(oldValue))
            }

            VStack(spacing: 6) {
                FieldRow(label: "Repeat", icon: "repeat") {
                    Picker("", selection: $draft.recurrence) {
                        if draft.originalRecurrence == .custom {
                            Text("Custom").tag(RecurrenceOption.custom)
                        }
                        ForEach(RecurrenceOption.pickable) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                FieldRow(label: "Alert", icon: "bell") {
                    Picker("", selection: $draft.alarm) {
                        ForEach(AlarmOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if draft.alarm != .none {
                    FieldRow(label: "Second alert", icon: "bell.badge") {
                        Picker("", selection: $draft.secondAlarm) {
                            ForEach(AlarmOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if !draft.isAllDay {
                    FieldRow(label: "Show as", icon: "eye") {
                        Picker("", selection: $draft.availability) {
                            ForEach(EventAvailability.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if context.isRecurring {
                    FieldRow(label: "Apply to future occurrences", icon: "calendar.badge.clock") {
                        Toggle("", isOn: $applyToFuture)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            VStack(spacing: 6) {
                FieldRow(label: "Location", icon: "mappin.and.ellipse") {
                    TextField("None", text: $draft.location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.trailing)
                }
                if !draft.isAllDay {
                    FieldRow(label: "Travel time", icon: "car") {
                        Picker("", selection: $draft.travelMinutes) {
                            Text("None").tag(0)
                            ForEach([5, 10, 15, 30, 45, 60], id: \.self) { m in
                                Text(Fmt.duration(minutes: m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if draft.travelMinutes > 0 {
                        Text("Adds a \(Fmt.duration(minutes: draft.travelMinutes)) travel block before this event.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if draft.linkedTaskID == nil {
                    FieldRow(label: "URL", icon: "link") {
                        TextField("None", text: $draft.urlString)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if !context.attendees.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ATTENDEES")
                        .font(.system(size: 11.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(context.attendees, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                            Text(name).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                TextEditor(text: $draft.notes)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if !isNew {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Text("Delete Block")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        .confirmationDialog(
            "Delete this block?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            if context.isRecurring {
                Button("Delete This Occurrence", role: .destructive) { delete(span: .thisEvent) }
                Button("Delete This and Future", role: .destructive) { delete(span: .futureEvents) }
            } else {
                Button("Delete", role: .destructive) { delete(span: .thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Calendar-default color plus a palette of per-block overrides.
    private var colorRow: some View {
        FieldRow(label: "Color", icon: "paintpalette") {
            HStack(spacing: 8) {
                Button {
                    draft.colorHex = nil
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(service.calendarInfo(withID: draft.calendarID)?.color ?? Theme.textTertiary)
                            .frame(width: 14, height: 14)
                        if draft.colorHex == nil {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Calendar default")

                ForEach(Palette.options, id: \.self) { hex in
                    Button {
                        draft.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(draft.colorHex == hex ? Theme.textPrimary : .clear, lineWidth: 2).padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func linkedTaskBanner(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Linked to reminder")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                Text(task.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Unlink") { draft.linkedTaskID = nil }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .background(Theme.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func save() {
        if let id = context.existingID {
            service.updateBlock(id: id, with: draft, span: applyToFuture ? .futureEvents : .thisEvent)
        } else {
            service.createBlock(draft)
        }
    }

    private func delete(span: EKSpan) {
        if let id = context.existingID {
            service.deleteBlock(id: id, span: span)
        }
        dismiss()
    }
}

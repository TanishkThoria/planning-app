import SwiftUI

/// Shared chrome for all Chronos sheets: dark surface, title bar with
/// cancel/confirm, and consistent sizing per platform.
struct EditorSheet<Content: View>: View {
    let title: String
    var confirmLabel = "Save"
    var confirmDisabled = false
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(confirmLabel) {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(confirmDisabled ? Theme.textTertiary : Color.accentColor)
                .disabled(confirmDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 460, height: 620)
        #endif
    }
}

/// Labeled row container for editor fields.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Big borderless title field at the top of editors.
struct TitleField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1...3)
    }
}

/// Duration preset chips (15m / 30m / …) used by the block editor.
struct DurationChips: View {
    let current: Int
    let onPick: (Int) -> Void

    private let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { minutes in
                Button {
                    onPick(minutes)
                } label: {
                    Text(Fmt.duration(minutes: minutes))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(current == minutes ? Theme.bg : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            current == minutes ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Calendar / reminder-list picker rendered as a menu with color dots.
struct CalendarPickerRow: View {
    let label: String
    let options: [CalendarInfo]
    @Binding var selection: String?

    private var selected: CalendarInfo? {
        options.first { $0.id == selection } ?? options.first
    }

    var body: some View {
        FieldRow(label: label) {
            Menu {
                ForEach(options.filter(\.isEditable)) { option in
                    Button {
                        selection = option.id
                    } label: {
                        Label(option.title, systemImage: selection == option.id ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(selected?.color ?? .gray).frame(width: 8, height: 8)
                    Text(selected?.title ?? "None")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize()
        }
    }
}

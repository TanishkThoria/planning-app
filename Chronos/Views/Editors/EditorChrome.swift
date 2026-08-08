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
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirmLabel)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(confirmDisabled ? Theme.textTertiary : Theme.onAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            confirmDisabled ? AnyShapeStyle(Theme.fill) : AnyShapeStyle(Theme.accentColor),
                            in: Capsule()
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(confirmDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Liquid-glass title bar that lifts off the content as it scrolls.
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(
            LinearGradient(colors: [Theme.accentColor.opacity(0.06), Theme.elevated],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 460, height: 620)
        #endif
    }
}

/// Labeled row container for editor fields. An optional leading icon renders a
/// tinted rounded-square chip (Apple Calendar / Reminders style) so rows read
/// at a glance.
struct FieldRow<Content: View>: View {
    let label: String
    var icon: String? = nil
    var iconTint: Color = Theme.accentColor
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(iconTint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, icon == nil ? 9 : 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1))
    }
}

/// Big borderless title field at the top of editors.
struct TitleField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 19, weight: .semibold))
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
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(current == minutes ? Theme.bg : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            current == minutes ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill),
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
    var icon: String? = nil

    private var selected: CalendarInfo? {
        options.first { $0.id == selection } ?? options.first
    }

    var body: some View {
        FieldRow(label: label, icon: icon) {
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize()
        }
    }
}

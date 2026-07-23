import SwiftUI

// MARK: - Permission gate

/// Shown until both Calendar and Reminders access are granted — Chronos
/// stores nothing itself, so it can't do anything without EventKit.
struct PermissionGateView: View {
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hexagon.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Chronos")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your time blocks live in Apple Calendar and your tasks in Apple Reminders — nothing is duplicated, everything stays in sync.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: 10) {
                statusRow("Calendar", granted: service.eventAccess == .granted)
                statusRow("Reminders", granted: service.reminderAccess == .granted)
            }
            .frame(maxWidth: 300)

            if service.wasDenied {
                VStack(spacing: 12) {
                    Text("Access was denied. Enable Calendars and Reminders for Chronos in system settings, then come back.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("Open Privacy Settings") { openPrivacySettings() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ChronosPrimaryButton("Connect & get started", icon: "sparkles", fullWidth: false) {
                    Task { await service.requestAccess() }
                }
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func statusRow(_ name: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Theme.success : Theme.textTertiary)
            Text(name)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(granted ? "Connected" : "Not connected")
                .font(.system(size: 12.5))
                .foregroundStyle(granted ? Theme.success : Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func openPrivacySettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Small shared pieces

/// Friendly section title — sentence case, readable weight, warm color. (It
/// used to be a tiny all-caps tracked micro-label, which read as technical and
/// cold; this warms every screen at once.)
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A big, warm empty state — a friendly tinted icon, a clear headline, a gentle
/// line of guidance, and (optionally) one obvious button to get moving.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 84, height: 84)
                .background(Theme.accentSoft(), in: Circle())
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                ChronosPrimaryButton(actionTitle, fullWidth: false, action: action)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}

/// The app's signature "colorful" accent: a bold white SF Symbol on a colored
/// gradient rounded square. Used for card headers, list rows, and tiles so the
/// whole app reads warm and friendly instead of a wall of gray glyphs.
struct IconChip: View {
    let icon: String
    var tint: Color = Theme.accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            )
            .shadow(color: tint.opacity(0.3), radius: size * 0.15, y: 2)
    }
}

/// A friendly palette for colorizing otherwise-monochrome icon rows/tiles —
/// pick by index so a group of chips reads varied and warm.
enum ChipPalette {
    static let colors: [Color] = [
        Color(hex: 0x5B6CF0), Color(hex: 0xFF7A59), Color(hex: 0x22C3C9),
        Color(hex: 0x3FC97A), Color(hex: 0x9C7BFA), Color(hex: 0xFFB23E),
        Color(hex: 0xFF6B9D), Color(hex: 0x4C9BFF),
    ]
    static func color(_ i: Int) -> Color { colors[((i % colors.count) + colors.count) % colors.count] }
    /// A stable color for a string (djb2 — unlike `hashValue`, consistent across
    /// launches), so a titled row keeps the same hue every time.
    static func color(for s: String) -> Color {
        var h = 5381
        for b in s.utf8 { h = (h &* 33) ^ Int(b) }
        return color(abs(h))
    }
}

// MARK: - Friendly buttons

/// Springy press feedback so taps feel tactile and alive.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

/// The big, in-your-face primary action — a tall, bold, rounded, accent-filled
/// button. The one obvious thing to tap on a screen.
struct ChronosPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.accentColor
    var fullWidth = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, tint: Color = Theme.accentColor,
         fullWidth: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint
        self.fullWidth = fullWidth; self.action = action
    }

    var body: some View {
        Button {
            Haptics.light(); action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(.system(size: 16.5, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 52)
            .padding(.horizontal, fullWidth ? 0 : 26)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: tint.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A softer companion — tinted fill, accent text — for the secondary choice.
struct ChronosSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.accentColor
    var fullWidth = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, tint: Color = Theme.accentColor,
         fullWidth: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint
        self.fullWidth = fullWidth; self.action = action
    }

    var body: some View {
        Button {
            Haptics.light(); action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 50)
            .padding(.horizontal, fullWidth ? 0 : 22)
            .background(Theme.accentSoft(tint), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Header nav cluster shared by day and week screens.
struct DateNavigator: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            navButton("chevron.left") { model.goBackward() }
            Button {
                model.goToToday()
            } label: {
                Text("Today")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(model.selectedDate.isToday ? Theme.textTertiary : Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedDate.isToday && model.screen == .calendar && model.plannerMode == .day)
            navButton("chevron.right") { model.goForward() }
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 26)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Round icon button used across screen headers — bigger, softer, and labelled
/// for VoiceOver. A prominent one fills with the accent to read as the primary
/// header action.
struct HeaderIconButton: View {
    let icon: String
    var label: String?
    var prominent = false
    /// VoiceOver name for icon-only buttons (falls back to the visible label).
    var accessibility: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: 14.5, weight: .semibold))
                }
            }
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textSecondary)
            .padding(.horizontal, label == nil ? 11 : 15)
            .frame(height: 38)
            .frame(minWidth: 38)
            .background(
                prominent ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .shadow(color: prominent ? Theme.accentColor.opacity(0.25) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label ?? accessibility ?? "")
    }
}

/// Completion ring used in headers and insights.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Theme.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: fraction)
    }
}

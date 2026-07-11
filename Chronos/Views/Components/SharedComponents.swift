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
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your time blocks live in Apple Calendar and your tasks in Apple Reminders — nothing is duplicated, everything stays in sync.")
                    .font(.system(size: 13))
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
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("Open Privacy Settings") { openPrivacySettings() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button {
                    Task { await service.requestAccess() }
                } label: {
                    Text("Grant Access")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(granted ? "Connected" : "Not connected")
                .font(.system(size: 11))
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

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.selectedDate.isToday ? Theme.textTertiary : Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedDate.isToday && model.screen == .day)
            navButton("chevron.right") { model.goForward() }
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 26)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Round icon button used across screen headers.
struct HeaderIconButton: View {
    let icon: String
    var label: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(prominent ? Theme.bg : Theme.textSecondary)
            .padding(.horizontal, label == nil ? 8 : 11)
            .frame(height: 26)
            .frame(minWidth: 28)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: fraction)
    }
}

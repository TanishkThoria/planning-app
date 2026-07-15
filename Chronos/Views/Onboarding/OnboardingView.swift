import SwiftUI

/// First-run tour: a short, polished walkthrough of what Chronos does, ending
/// with the permission requests it needs. Step-based (not swipe-only) so it
/// behaves identically on iOS and macOS. Shown once, gated by the
/// `chronos.onboardingComplete` preference in RootView.
struct OnboardingView: View {
    /// Passes back whether the student opted to connect their school LMS.
    var onFinish: (_ connectLMS: Bool) -> Void

    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var notifications: NotificationService
    @AppStorage(Prefs.accentName) private var accentName = "Blue"

    @State private var step = 0
    @State private var requestingAccess = false
    @State private var requestingNotifications = false
    @State private var wantsLMS = false

    private let pages = OnboardingPage.all

    /// Total steps = intro pages + one permissions page.
    private var lastStep: Int { pages.count }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    if step < pages.count {
                        pageContent(pages[step])
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id(step)
                    } else {
                        permissionsContent
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 460, maxHeight: .infinity)
                .frame(maxWidth: .infinity)

                controls
            }
        }
        .chronosAppearance()
        .tint(Theme.accent(named: accentName))
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    // MARK: Top bar (progress + skip)

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.accentColor : Theme.fill)
                        .frame(width: i == step ? 20 : 6, height: 6)
                        .animation(.snappy, value: step)
                }
            }
            Spacer()
            if step < lastStep {
                Button("Skip") { finish() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: Intro page

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 108, height: 108)
                Image(systemName: page.icon)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)

            if !page.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.bullets, id: \.text) { bullet in
                        HStack(spacing: 12) {
                            Image(systemName: bullet.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            Text(bullet.text)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: Permissions page

    private var permissionsContent: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 108, height: 108)
                Image(systemName: "lock.shield")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 10) {
                Text("A couple of permissions")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Chronos stores everything in your own Apple Calendar and Reminders — nothing lives on a server.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)

            VStack(spacing: 10) {
                permissionRow(
                    icon: "calendar",
                    title: "Calendar & Reminders",
                    subtitle: "Required — your blocks and tasks live here.",
                    granted: service.hasFullAccess,
                    busy: requestingAccess
                ) { requestAccess() }

                permissionRow(
                    icon: "bell.badge",
                    title: "Notifications",
                    subtitle: "Optional — check-ins, ritual nudges, habit reminders.",
                    granted: notifications.authorization == .authorized,
                    busy: requestingNotifications
                ) { requestNotifications() }

                Button { wantsLMS.toggle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I'm a student")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Connect Canvas or Schoology after setup — assignments become reminders automatically.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: wantsLMS ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(wantsLMS ? Theme.success : Theme.textTertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(wantsLMS ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func permissionRow(icon: String, title: String, subtitle: String, granted: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.success)
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Enable", action: action)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(step < lastStep ? "Continue" : "Start planning")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            if step > 0 {
                Button("Back") {
                    withAnimation(.snappy) { step -= 1 }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: Actions

    private func advance() {
        if step < lastStep {
            withAnimation(.snappy) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        onFinish(wantsLMS)
    }

    private func requestAccess() {
        requestingAccess = true
        Task {
            await service.requestAccess()
            requestingAccess = false
        }
    }

    private func requestNotifications() {
        requestingNotifications = true
        Task {
            let granted = await notifications.requestAuthorization()
            if granted { notifications.enabled = true }
            requestingNotifications = false
        }
    }
}

/// One intro screen's content.
struct OnboardingPage {
    struct Bullet { let icon: String; let text: String }
    let icon: String
    let title: String
    let subtitle: String
    var bullets: [Bullet] = []

    static let all: [OnboardingPage] = [
        OnboardingPage(
            icon: "hourglass",
            title: "Welcome to Chronos",
            subtitle: "A calm, powerful way to plan your time — and actually live your priorities."
        ),
        OnboardingPage(
            icon: "calendar.day.timeline.left",
            title: "Time-block your day",
            subtitle: "Drag tasks onto a beautiful timeline. Every block is a real Apple Calendar event.",
            bullets: [
                .init(icon: "hand.draw", text: "Double-tap the timeline to create a block"),
                .init(icon: "arrow.up.and.down", text: "Drag to move, pull the edge to resize"),
                .init(icon: "paintpalette", text: "Color-code blocks and chunk long work")
            ]
        ),
        OnboardingPage(
            icon: "checklist",
            title: "Tasks, done right",
            subtitle: "Your Apple Reminders, supercharged with estimates, energy, and priority.",
            bullets: [
                .init(icon: "square.grid.2x2", text: "Eisenhower matrix to triage what matters"),
                .init(icon: "list.bullet.indent", text: "Subtasks and per-list organization"),
                .init(icon: "bolt", text: "Auto-schedule tasks into free slots")
            ]
        ),
        OnboardingPage(
            icon: "leaf",
            title: "Grow every day",
            subtitle: "Build the person behind the schedule with habits, goals, and reflection.",
            bullets: [
                .init(icon: "flame", text: "Habits with streaks and gentle nudges"),
                .init(icon: "target", text: "Goals that connect to your weeks"),
                .init(icon: "sunrise", text: "Morning and evening rituals, grounded in research")
            ]
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Coach, focus & insights",
            subtitle: "An on-device planning companion, plus the tools and numbers that keep you moving.",
            bullets: [
                .init(icon: "bubble.left.and.text.bubble.right", text: "Ask your Coach what to focus on — from Today or ⌘K"),
                .init(icon: "timer", text: "Pomodoro & focus timer with a Live Activity"),
                .init(icon: "chart.bar.fill", text: "An Insights tab: momentum, trends & your Year in Review")
            ]
        )
    ]
}

import SwiftUI

/// Year in Review — the "Chronos Wrapped" moment. A scrollable set of bold
/// story cards celebrating the year's real numbers, ending in a shareable
/// recap. Computed entirely on-device.
struct WrappedView: View {
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var summary: WrappedEngine.Summary?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let summary {
                if summary.hasEnoughData {
                    content(summary)
                } else {
                    notEnough
                }
            } else {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
        .task {
            summary = await WrappedEngine.compute(service: service, focusLog: focusLog, life: life)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Year in Review")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var notEnough: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("📆").font(.system(size: 40))
            Text("Not much to wrap up yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Keep planning, focusing, and building habits — your Year in Review fills in as the year goes on.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Spacer()
        }
    }

    private func content(_ s: WrappedEngine.Summary) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard(s)
                heroStat("\(s.focusHours)", "hours focused", "\(s.focusSessions) sessions · longest \(Fmt.duration(minutes: s.longestFocusMinutes))", "timer", [Color.accentColor, Color.accentColor.opacity(0.5)])
                heroStat("\(s.scheduledHours)", "hours time-blocked", "\(s.blockCount) blocks placed on your calendar", "rectangle.stack.fill", [Theme.success, Theme.success.opacity(0.5)])
                heroStat("\(s.tasksCompleted)", "tasks completed", s.mostProductiveWeekday.map { "\($0)s were your most productive day" } ?? "one done thing at a time", "checkmark.circle.fill", [Color(hex: 0xF2B95C), Color(hex: 0xF0719B)])
                if s.deepHours > 0 {
                    heroStat("\(s.deepHours)", "hours of deep work", "the hard, valuable stuff", "brain.head.profile", [Color(hex: 0x7C8CF8), Color(hex: 0x4FD1C5)])
                }
                if s.bestHabitStreak > 0 {
                    heroStat("\(s.bestHabitStreak)", "day best habit streak", "showing up, again and again", "flame.fill", [Theme.warning, Theme.danger])
                }
                if !s.topCalendars.isEmpty { topCalendarsCard(s) }
                shareCard(s)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private func heroCard(_ s: WrappedEngine.Summary) -> some View {
        VStack(spacing: 8) {
            Text("YOUR \(s.periodLabel)")
                .font(.system(size: 13, weight: .bold)).tracking(3)
                .foregroundStyle(.white.opacity(0.8))
            Text("in time")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Here's where your hours went.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            LinearGradient(colors: [Color.accentColor, Color(hex: 0xF0719B)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func heroStat(_ value: String, _ label: String, _ caption: String, _ icon: String, _ colors: [Color]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func topCalendarsCard(_ s: WrappedEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHERE YOUR TIME WENT")
                .font(.system(size: 10, weight: .bold)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(s.topCalendars.enumerated()), id: \.element.id) { idx, entry in
                HStack(spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.color)
                        .frame(width: 24)
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.minutes / 60)h")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shareCard(_ s: WrappedEngine.Summary) -> some View {
        ShareLink(item: shareText(s)) {
            Label("Share my \(s.periodLabel)", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func shareText(_ s: WrappedEngine.Summary) -> String {
        var lines = ["My \(s.periodLabel) in Chronos:"]
        lines.append("⏱ \(s.focusHours)h focused across \(s.focusSessions) sessions")
        lines.append("📅 \(s.scheduledHours)h time-blocked")
        lines.append("✅ \(s.tasksCompleted) tasks done")
        if s.deepHours > 0 { lines.append("🧠 \(s.deepHours)h of deep work") }
        if s.bestHabitStreak > 0 { lines.append("🔥 \(s.bestHabitStreak)-day best habit streak") }
        return lines.joined(separator: "\n")
    }
}

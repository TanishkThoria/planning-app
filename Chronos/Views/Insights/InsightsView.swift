import SwiftUI

/// The Insights tab — one home for everything that used to be scattered across
/// the Coach header, the Grow tab, and the command bar. Momentum up top, a
/// week-at-a-glance strip, then a card for each deeper report. Nothing about
/// your progress is more than a tap from here.
struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var momentum = MomentumStore.shared
    @ObservedObject private var paid = PaidFeatures.shared
    @ObservedObject private var social = SocialService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Metric.screen)
                .padding(.top, 16)
                .padding(.bottom, 14)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MomentumCard()
                    weekStrip
                    reportsSection
                    socialSection
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .task { if paid.isReady(.friends) { await social.refreshFriends() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your momentum & progress")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "command") { model.commandBarPresented = true }
            #if os(iOS)
            HeaderIconButton(icon: "gearshape") { model.settingsPresented = true }
            #endif
        }
    }

    // MARK: Week-at-a-glance

    private var weekStrip: some View {
        let s = weekStats
        return HStack(spacing: 10) {
            statTile("timer", "Focus", Fmt.duration(minutes: s.focusMinutes), Theme.success)
            statTile("checkmark.circle", "Done", "\(s.tasksCompleted)", Theme.accentColor)
            statTile("flame", "Streak", "\(s.streakDays)d", .orange)
            statTile("chart.pie", "On time", "\(Int((s.completionRate * 100).rounded()))%", .purple)
        }
    }

    private func statTile(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Reports

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Reports")
                .padding(.horizontal, 2)
            VStack(spacing: 10) {
                reportCard("chart.bar.xaxis", "Statistics", "Completion, focus, budgets & achievements") {
                    model.statsPresented = true
                }
                reportCard("clock.arrow.circlepath", "Where your time goes", "A breakdown of how you actually spent it") {
                    model.timeReportPresented = true
                }
                reportCard("chart.line.uptrend.xyaxis", "Trends", "Mood, habits, goals & reflections over time") {
                    model.trendsPresented = true
                }
                reportCard("gift", "Year in Review", "Your planning story, wrapped") {
                    model.wrappedPresented = true
                }
                reportCard("chart.pie", "Time budgets", "Set targets and track where hours land") {
                    model.budgetsPresented = true
                }
            }
        }
    }

    // MARK: Social (Chronos+)

    private var focusingFriends: [FriendStatus] {
        social.friends.filter { $0.isLive && $0.presence.busy == .headsDown }
    }

    @ViewBuilder
    private var focusTogetherCard: some View {
        if !focusingFriends.isEmpty {
            Button { model.startFocus(taskID: nil, title: "Focus") } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -8) {
                        ForEach(focusingFriends.prefix(3)) { f in
                            Avatar(name: f.presence.displayName, emoji: f.presence.statusEmoji, size: 32)
                                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(focusingFriends.count) focusing now")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Study alongside them — start a session too")
                            .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "timer").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Theme.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
                    .strokeBorder(Theme.accentColor.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Compete")
                .padding(.horizontal, 2)
            VStack(spacing: 10) {
                focusTogetherCard
                reportCard("trophy", "Leaderboard", paid.isReady(.leaderboards)
                           ? "Weekly focus & momentum, ranked with friends"
                           : "Rank your focus with friends — a Chronos+ feature", tag: "Chronos+") {
                    model.leaderboardPresented = true
                }
                reportCard("person.2", "Friends", paid.isReady(.friends)
                           ? "See what your friends are focusing on"
                           : "Follow friends' focus — a Chronos+ feature", tag: "Chronos+") {
                    model.friendsPresented = true
                }
            }
        }
    }

    private func reportCard(_ icon: String, _ title: String, _ subtitle: String, tag: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let tag {
                            Text(tag)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private var weekStats: StatsEngine.Stats {
        let start = Date().startOfWeek
        let days = (0..<7).map { start.adding(days: $0) }
        return StatsEngine.compute(
            days: days,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions
        )
    }
}

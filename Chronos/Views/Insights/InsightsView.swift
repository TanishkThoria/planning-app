import SwiftUI

/// The Insights tab — one home for everything that used to be scattered across
/// the Coach header, the Grow tab, and the command bar. Momentum up top, a
/// week-at-a-glance strip, then a card for each deeper report. Nothing about
/// your progress is more than a tap from here.
struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @ObservedObject private var momentum = MomentumStore.shared
    @ObservedObject private var challenges = ChallengeStore.shared
    @ObservedObject private var paid = PaidFeatures.shared
    @ObservedObject private var social = SocialService.shared

    private var achievements: [Achievement] {
        AchievementEngine.compute(
            AchievementEngine.liveInputs(service: service, life: life, focusLog: focusLog,
                                         hiddenCalendars: model.hiddenCalendarIDs)
        )
    }

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
                    challengesCard
                    gamificationCard
                    projectTimeCard
                    reportsSection
                    // Shown per-capability, so a build with Game Center (but not
                    // CloudKit yet) surfaces the leaderboard without advertising
                    // friends it can't run.
                    if paid.isEntitled(.leaderboards) || paid.isEntitled(.friends) {
                        socialSection
                    }
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Challenges

    private var challengesCard: some View {
        let m = ChallengeMetrics.live(service: service, life: life, focusLog: focusLog,
                                      hiddenCalendars: model.hiddenCalendarIDs)
        let daily = challenges.dailyChallenges()
        let doneCount = daily.filter { challenges.isComplete($0) }.count
        return VStack(alignment: .leading, spacing: 12) {
            Button { model.challengesPresented = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered").font(.system(size: 14.5)).foregroundStyle(Theme.accentColor)
                    Text("Daily Challenges").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(doneCount)/\(daily.count)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            VStack(spacing: 8) {
                ForEach(daily) { challenge in
                    ChallengeRow(challenge: challenge,
                                 value: challenges.value(challenge, m),
                                 done: challenges.isComplete(challenge))
                }
            }
        }
        .panel()
    }

    // MARK: Gamification (achievements + records)

    private var gamificationCard: some View {
        let unlocked = achievements.filter(\.unlocked)
        let ordered = unlocked + achievements.filter { !$0.unlocked }.sorted { $0.progress > $1.progress }
        return VStack(alignment: .leading, spacing: 12) {
            Button { model.achievementsPresented = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").font(.system(size: 14.5)).foregroundStyle(Color(hex: 0xF2C14E))
                    Text("Achievements").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(unlocked.count)/\(achievements.count)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ordered.prefix(12)) { badge in
                        Button { model.achievementsPresented = true } label: { badgeChip(badge) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 0) {
                miniRecord("flame.fill", "\(momentum.bestStreak())d", "Best streak", .orange)
                recordDivider
                miniRecord("star.circle.fill", "\(momentum.perfectDays)", "Perfect days", Color(hex: 0xF2C14E))
                recordDivider
                miniRecord("bolt.fill", "Lv \(momentum.level)", momentum.levelTitle, Theme.accentColor)
            }
        }
        .panel()
    }

    private func badgeChip(_ badge: Achievement) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill((badge.unlocked ? badge.tier.color : Theme.textTertiary).opacity(badge.unlocked ? 0.2 : 0.1))
                    .frame(width: 46, height: 46)
                if !badge.unlocked {
                    Circle().trim(from: 0, to: max(0.02, badge.progress))
                        .stroke(Theme.textTertiary.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
                }
                Image(systemName: badge.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(badge.unlocked ? badge.tier.color : Theme.textTertiary)
            }
            Text(badge.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(badge.unlocked ? Theme.textSecondary : Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 58)
        }
    }

    private func miniRecord(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var recordDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 28)
    }

    // MARK: Project time

    /// Time banked on long-term projects — logged by hand or auto-captured from
    /// project-tagged focus sessions. Hidden until there's something to show.
    @ViewBuilder
    private var projectTimeCard: some View {
        let ranked = life.activeProjects
            .filter { $0.totalLoggedMinutes > 0 }
            .sorted {
                $0.loggedMinutes() == $1.loggedMinutes()
                    ? $0.totalLoggedMinutes > $1.totalLoggedMinutes
                    : $0.loggedMinutes() > $1.loggedMinutes()
            }
        if !ranked.isEmpty {
            let weekTotal = ranked.reduce(0) { $0 + $1.loggedMinutes() }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Project time")
                    Spacer()
                    Text("\(Fmt.duration(minutes: weekTotal)) this week")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                VStack(spacing: 8) {
                    ForEach(ranked.prefix(5)) { project in
                        HStack(spacing: 10) {
                            ProjectRing(progress: project.progress, color: project.color, emoji: project.emoji, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.title.isEmpty ? "Untitled project" : project.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Text("\(Fmt.duration(minutes: project.totalLoggedMinutes)) total")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Text(Fmt.duration(minutes: project.loggedMinutes()))
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(project.loggedMinutes() > 0 ? project.color : Theme.textTertiary)
                        }
                    }
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
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
                if paid.isEntitled(.friends) {
                    focusTogetherCard
                }
                if paid.isEntitled(.leaderboards) {
                    reportCard("trophy", "Leaderboard", paid.isEntitled(.friends)
                               ? "Weekly focus & momentum, ranked with friends"
                               : "Rank your focus on Apple's Game Center", tag: "Chronos+") {
                        model.leaderboardPresented = true
                    }
                }
                if paid.isEntitled(.friends) {
                    reportCard("person.2", "Friends", paid.isReady(.friends)
                               ? "See what your friends are focusing on"
                               : "Follow friends' focus — a Chronos+ feature", tag: "Chronos+") {
                        model.friendsPresented = true
                    }
                    reportCard("flag.2.crossed", "Duels", "Challenge a friend head-to-head for a week", tag: "Chronos+") {
                        model.friendChallengesPresented = true
                    }
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
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
        )
    }
}

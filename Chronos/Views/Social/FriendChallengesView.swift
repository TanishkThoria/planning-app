import SwiftUI

/// Head-to-head duels with friends: pick someone, pick a metric, and race for a
/// week. Scores read live from each side's presence. Rides the `.friends`
/// capability, so it shows a "ready with Chronos+" state until that's enabled
/// (post-transfer) and never touches the network before then.
struct FriendChallengesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var paid = PaidFeatures.shared

    @State private var pickedFriendCode: String?
    @State private var pickedMetric: LeaderboardBoard = .focusWeek

    private var active: [Duel] { social.duels.filter { !$0.isFinished } }
    private var finished: [Duel] { social.duels.filter { $0.isFinished } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if paid.isEntitled(.friends) {
                        composer
                        if !active.isEmpty {
                            SectionHeader(title: "In play")
                            ForEach(active) { duelCard($0) }
                        }
                        if !finished.isEmpty {
                            SectionHeader(title: "Recent")
                            ForEach(finished) { duelCard($0) }
                        }
                        if social.duels.isEmpty { emptyState }
                    } else {
                        lockedNote
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Duels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .task { if paid.isReady(.friends) { await social.refreshFriends() } }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "flag.2.crossed.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accentColor)
                Text("Duels").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            Text("Go head-to-head with a friend for a week — most focus, highest momentum, or longest streak wins. Live scores, no check-ins.")
                .font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accentColor.opacity(0.18), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var lockedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ready with Chronos+", systemImage: "lock.open")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentColor)
            Text("Duels use your friends list, which runs on your private iCloud with Chronos+. The whole feature is built and waiting — it lights up the moment Friends is enabled, no update needed.")
                .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            metricPreview
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var metricPreview: some View {
        HStack(spacing: 8) {
            ForEach(LeaderboardBoard.allCases) { board in
                VStack(spacing: 5) {
                    Image(systemName: board.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    Text(board.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "New duel")
            if social.friends.isEmpty {
                Text("Add a friend first — then challenge them here.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(social.friends) { f in
                            Button(f.presence.displayName) { pickedFriendCode = f.presence.code }
                        }
                    } label: {
                        menuLabel(icon: "person.fill",
                                  text: social.friends.first { $0.presence.code == pickedFriendCode }?.presence.displayName ?? "Pick a friend")
                    }
                    Menu {
                        ForEach(LeaderboardBoard.allCases) { board in
                            Button { pickedMetric = board } label: { Label(board.title, systemImage: board.icon) }
                        }
                    } label: {
                        menuLabel(icon: pickedMetric.icon, text: pickedMetric.title)
                    }
                }
                Button {
                    if let code = pickedFriendCode { social.sendDuel(to: code, metric: pickedMetric); Haptics.success() }
                } label: {
                    Text("Send challenge · 7 days")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(pickedFriendCode == nil ? Theme.textTertiary : Theme.bg)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(pickedFriendCode == nil ? AnyShapeStyle(Theme.fill) : AnyShapeStyle(Theme.accentColor),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(pickedFriendCode == nil)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func menuLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
            Text(text).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Duel card

    private func duelCard(_ duel: Duel) -> some View {
        let scores = social.duelScores(duel)
        let leader = max(scores.mine, scores.theirs, 1)
        let youWin = scores.mine >= scores.theirs
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: duel.metric.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                Text("\(duel.metric.title) · vs \(social.opponentName(duel))")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Text(statusText(duel))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(duel.isFinished ? (youWin ? Theme.success : Theme.textTertiary) : Theme.textSecondary)
            }
            duelBar("You", scores.mine, leader: leader, tint: youWin ? Theme.success : Theme.accentColor,
                    metric: duel.metric)
            duelBar(social.opponentName(duel), scores.theirs, leader: leader,
                    tint: youWin ? Theme.textTertiary : Theme.warning, metric: duel.metric)
            if social.isIncoming(duel) {
                Button { social.acceptDuel(duel); Haptics.success() } label: {
                    Text("Accept challenge")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func duelBar(_ name: String, _ value: Int, leader: Int, tint: Color, metric: LeaderboardBoard) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(tint).frame(width: max(4, geo.size.width * (Double(value) / Double(leader))))
                }
            }
            .frame(height: 8)
            Text(metric.display(value)).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .frame(width: 54, alignment: .trailing).monospacedDigit()
        }
    }

    private func statusText(_ duel: Duel) -> String {
        if duel.isFinished {
            let scores = social.duelScores(duel)
            return scores.mine >= scores.theirs ? "You won 🏆" : "You lost"
        }
        if social.isIncoming(duel) { return "Invited you" }
        if duel.isPending { return "Pending" }
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: duel.endDate).day ?? 0)
        return "\(days)d left"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.2.crossed").font(.system(size: 30)).foregroundStyle(Theme.accentColor)
            Text("No duels yet").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Challenge a friend above and the race is on.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

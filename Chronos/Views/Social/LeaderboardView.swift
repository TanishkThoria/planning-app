import SwiftUI

/// Weekly focus + all-time momentum leaderboards, backed by Game Center. When
/// the capability isn't available it shows your local standing and how to
/// unlock ranking with friends — never a dead end.
struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var paid = PaidFeatures.shared
    @ObservedObject private var momentum = MomentumStore.shared

    private var weeklyFocusMinutes: Int { focusLog.totalMinutes(inLast: 7) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    yourStanding
                    if paid.isEntitled(.leaderboards) {
                        gameCenterCard
                    } else {
                        lockedCard
                    }
                    howItWorks
                }
                .padding(18)
                .frame(maxWidth: 520, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Leaderboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .chronosAppearance()
        .onAppear {
            if paid.isReady(.leaderboards) { social.authenticateGameCenter() }
        }
    }

    private var yourStanding: some View {
        HStack(spacing: 12) {
            statTile(
                icon: "timer", label: "This week",
                value: Fmt.duration(minutes: weeklyFocusMinutes), tint: Theme.success
            )
            statTile(
                icon: "bolt.fill", label: "Momentum",
                value: "\(momentum.totalPoints)", tint: Color.accentColor
            )
        }
    }

    private func statTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var gameCenterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: social.gameCenterAuthenticated ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(social.gameCenterAuthenticated ? Theme.success : Theme.warning)
                Text(social.gameCenterAuthenticated ? "Game Center connected" : "Connect Game Center")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(social.gameCenterAuthenticated
                 ? "Your weekly focus and momentum are submitted automatically. Rankings appear in Game Center."
                 : "Sign in to Game Center to rank your focus and momentum against friends.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !social.gameCenterAuthenticated {
                Button {
                    social.authenticateGameCenter()
                } label: {
                    Label("Sign in to Game Center", systemImage: "gamecontroller")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    social.submitWeeklyFocus(minutes: weeklyFocusMinutes)
                    social.submitMomentum(momentum.totalPoints)
                    Haptics.success()
                } label: {
                    Label("Submit my scores now", systemImage: "arrow.up.circle")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ranking is a Chronos+ feature", systemImage: "lock.fill")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Your weekly focus and momentum are already tracked above. Rank them against friends by turning on Chronos+ — it uses Apple's Game Center, no account needed beyond your Apple ID.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var howItWorks: some View {
        Text("Focus minutes come from your focus sessions; momentum is your all-time points. Both update automatically as you plan and work.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

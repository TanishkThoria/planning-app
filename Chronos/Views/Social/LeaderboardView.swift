import SwiftUI

/// A friends leaderboard computed live from everyone's shared presence — no
/// Game Center required, and you're always on it. Switch between Focus,
/// Momentum, and Streak boards; a podium crowns the top three. Game Center is
/// offered as an optional extra when Chronos+ is on.
struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var paid = PaidFeatures.shared
    @ObservedObject private var momentum = MomentumStore.shared

    @State private var board: LeaderboardBoard = .focusWeek

    private var rows: [LeaderboardRow] { social.leaderboard(board) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    boardPicker
                    if rows.count <= 1 {
                        soloState
                    } else {
                        podium
                        standings
                    }
                    if paid.isEntitled(.leaderboards) { gameCenterCard }
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Leaderboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .task {
            await social.refreshFriends()
            if paid.isReady(.leaderboards) { social.authenticateGameCenter() }
        }
    }

    // MARK: Board switcher

    private var boardPicker: some View {
        Picker("", selection: $board) {
            ForEach(LeaderboardBoard.allCases) { b in
                Text(b.title).tag(b)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Podium

    private var podium: some View {
        let top = Array(rows.prefix(3))
        return HStack(alignment: .bottom, spacing: 12) {
            if top.count > 1 { podiumColumn(top[1], height: 96, medal: "2") }
            if let first = top.first { podiumColumn(first, height: 124, medal: "1") }
            if top.count > 2 { podiumColumn(top[2], height: 78, medal: "3") }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func podiumColumn(_ row: LeaderboardRow, height: CGFloat, medal: String) -> some View {
        VStack(spacing: 8) {
            Avatar(name: row.presence.displayName, emoji: row.presence.statusEmoji,
                   size: medal == "1" ? 56 : 46, ring: row.isYou)
            Text(row.isYou ? "You" : row.presence.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(board.display(row.value))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(medalColor(medal).opacity(0.18))
                    .frame(height: height)
                Text(medal)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(medalColor(medal))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func medalColor(_ medal: String) -> Color {
        switch medal {
        case "1": return Color(hex: 0xF2C14E)
        case "2": return Color(hex: 0xB9C2CF)
        default: return Color(hex: 0xCD8B5A)
        }
    }

    // MARK: Full standings

    private var standings: some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22)
                    Avatar(name: row.presence.displayName, emoji: row.presence.statusEmoji, size: 34, ring: row.isYou)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.isYou ? "You" : row.presence.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(row.presence.levelTitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(board.display(row.value))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(row.isYou ? Theme.accentColor : Theme.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(row.isYou ? Theme.accentColor.opacity(0.08) : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
                    .strokeBorder(row.isYou ? Theme.accentColor.opacity(0.35) : Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var soloState: some View {
        VStack(spacing: 10) {
            Image(systemName: board.icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.accentColor)
            Text(board.display(board.value(social.myPresence)))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add friends to see how you stack up. Your \(board.title.lowercased()) is ready to race.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: Game Center (extra)

    private var gameCenterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: social.gameCenterAuthenticated ? "checkmark.seal.fill" : "gamecontroller")
                    .foregroundStyle(social.gameCenterAuthenticated ? Theme.success : Theme.accentColor)
                Text(social.gameCenterAuthenticated ? "Also ranking on Game Center" : "Add Game Center ranking")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(social.gameCenterAuthenticated
                 ? "Your focus and momentum are submitted to Apple's global leaderboards too."
                 : "Sign in to also rank on Apple's Game Center leaderboards.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !social.gameCenterAuthenticated {
                Button { social.authenticateGameCenter() } label: {
                    Text("Sign in to Game Center")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// A round avatar: a colored monogram, an optional status emoji badge, and an
/// optional accent ring for "you".
struct Avatar: View {
    let name: String
    var emoji: String = ""
    var size: CGFloat = 40
    var ring: Bool = false

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    private var tint: Color {
        let palette: [UInt32] = [0x7C8CF8, 0x4FD1C5, 0xF2B95C, 0xF0719B, 0xA3E06B, 0x9B8CFF]
        let idx = abs(name.hashValue) % palette.count
        return Color(hex: palette[idx])
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundStyle(tint)
                )
                .overlay(
                    Circle().strokeBorder(ring ? Theme.accentColor : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
            if !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.34))
                    .padding(2)
                    .background(Theme.surface, in: Circle())
            }
        }
    }
}

import SwiftUI

/// The challenges board: a rotating set of daily and weekly goals that pay out
/// bonus XP when you clear them. Progress is read live from your real activity,
/// so there's nothing to check in — just do the thing.
struct ChallengesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var store = ChallengeStore.shared
    @ObservedObject private var momentum = MomentumStore.shared
    @Environment(\.dismiss) private var dismiss

    private var metrics: ChallengeMetrics {
        ChallengeMetrics.live(service: service, life: life, focusLog: focusLog,
                              hiddenCalendars: model.hiddenCalendarIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let m = metrics
                VStack(alignment: .leading, spacing: 20) {
                    xpHeader(m)
                    challengeSection("Today", store.dailyChallenges(), m, resets: "Resets at midnight")
                    challengeSection("This week", store.weeklyChallenges(), m, resets: "Resets Monday")
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Challenges")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
    }

    private func xpHeader(_ m: ChallengeMetrics) -> some View {
        let all = store.dailyChallenges() + store.weeklyChallenges()
        let done = all.filter { store.isComplete($0) }.count
        let earnable = all.reduce(0) { $0 + $1.xp }
        let earned = all.filter { store.isComplete($0) }.reduce(0) { $0 + $1.xp }
        return HStack(spacing: 14) {
            IconChip(icon: "flag.checkered", tint: Color(hex: 0xFFB23E), size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(done) of \(all.count) cleared")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("\(earned) of \(earnable) XP earned this cycle · Lv \(momentum.level)")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accentColor.opacity(0.16), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func challengeSection(_ title: String, _ challenges: [Challenge], _ m: ChallengeMetrics, resets: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: title)
                Spacer()
                Text(resets).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            VStack(spacing: 8) {
                ForEach(challenges) { challenge in
                    ChallengeRow(challenge: challenge,
                                 value: store.value(challenge, m),
                                 done: store.isComplete(challenge))
                }
            }
        }
    }
}

/// A single challenge with its progress bar and XP payout.
struct ChallengeRow: View {
    let challenge: Challenge
    let value: Int
    let done: Bool

    private var color: Color { Color(hex: challenge.colorHex) }
    private var progress: Double { challenge.target <= 0 ? 1 : min(1, Double(value) / Double(challenge.target)) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(done ? 0.22 : 0.14)).frame(width: 42, height: 42)
                Image(systemName: done ? "checkmark" : challenge.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(challenge.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("+\(challenge.xp) XP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(done ? Theme.success : color)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background((done ? Theme.success : color).opacity(0.15), in: Capsule())
                    Spacer(minLength: 0)
                    Text(done ? "Done" : "\(min(value, challenge.target))/\(challenge.target)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                        .monospacedDigit()
                }
                Text(challenge.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(done ? Theme.success : color)
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(done ? Theme.success.opacity(0.3) : Theme.hairline, lineWidth: 1))
    }
}

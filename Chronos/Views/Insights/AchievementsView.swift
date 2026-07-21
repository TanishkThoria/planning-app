import SwiftUI

/// The trophy room: a level + records header, then every badge with its full
/// description and live progress — unlocked ones up top, the rest sorted by how
/// close you are. The gamification layer's home.
struct AchievementsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var momentum = MomentumStore.shared
    @Environment(\.dismiss) private var dismiss

    private var achievements: [Achievement] {
        AchievementEngine.compute(
            AchievementEngine.liveInputs(service: service, life: life, focusLog: focusLog,
                                         hiddenCalendars: model.hiddenCalendarIDs)
        )
    }

    private var unlocked: [Achievement] { achievements.filter(\.unlocked) }
    private var locked: [Achievement] {
        achievements.filter { !$0.unlocked }.sorted { $0.progress > $1.progress }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    recordsRow
                    if !unlocked.isEmpty {
                        section("Earned", unlocked, "\(unlocked.count)")
                    }
                    if !locked.isEmpty {
                        section("In progress", locked, "\(locked.count)")
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Achievements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
    }

    // MARK: Hero (level + XP)

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.accentColor.opacity(0.16), lineWidth: 6).frame(width: 74, height: 74)
                Circle().trim(from: 0, to: max(0.02, momentum.progressToNextLevel))
                    .stroke(Theme.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 74, height: 74)
                VStack(spacing: 0) {
                    Text("\(momentum.level)").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("LVL").font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(momentum.levelTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(momentum.pointsIntoLevel)/500 XP to level \(momentum.level + 1)")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Text("\(unlocked.count) of \(achievements.count) badges earned")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accentColor)
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

    // MARK: Records

    private var recordsRow: some View {
        HStack(spacing: 10) {
            recordTile("flame.fill", "\(momentum.bestStreak())d", "Best streak", .orange)
            recordTile("star.circle.fill", "\(momentum.perfectDays)", "Perfect days", Color(hex: 0xF2C14E))
            recordTile("shield.lefthalf.filled", "\(momentum.solidDays)", "Solid days", Theme.success)
            recordTile("bolt.fill", "\(momentum.totalPoints)", "Total XP", Theme.accentColor)
        }
    }

    private func recordTile(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Sections

    private func section(_ title: String, _ items: [Achievement], _ count: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, trailing: count)
            VStack(spacing: 8) {
                ForEach(items) { badge in achievementRow(badge) }
            }
        }
    }

    private func achievementRow(_ badge: Achievement) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill((badge.unlocked ? badge.tier.color : Theme.textTertiary).opacity(badge.unlocked ? 0.2 : 0.12))
                    .frame(width: 46, height: 46)
                if !badge.unlocked {
                    Circle().trim(from: 0, to: max(0.02, badge.progress))
                        .stroke(Theme.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
                }
                Image(systemName: badge.icon)
                    .font(.system(size: 19))
                    .foregroundStyle(badge.unlocked ? badge.tier.color : Theme.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(badge.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    tierPill(badge.tier)
                }
                Text(badge.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if badge.unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(badge.tier.color)
            } else {
                Text(badge.progressText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(badge.unlocked ? badge.tier.color.opacity(0.28) : Theme.hairline, lineWidth: 1))
    }

    private func tierPill(_ tier: AchievementTier) -> some View {
        Text(tier.label.uppercased())
            .font(.system(size: 8.5, weight: .bold)).tracking(0.5)
            .foregroundStyle(tier.color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(tier.color.opacity(0.16), in: Capsule())
    }
}

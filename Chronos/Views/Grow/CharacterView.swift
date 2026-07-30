import SwiftUI

/// The character sheet: your level and the six attributes of the person you're
/// building, each levelled purely by evidence. No sliders — Fitness rises when
/// you train, Knowledge when you study, Discipline when you keep showing up.
struct CharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var momentum = MomentumStore.shared

    var body: some View {
        let readings = AttributeEngine.readings(life: life, focus: focusLog, tasks: service.tasks)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    attributesSection(readings)
                    if let note = growthNote(readings) { note }
                    footer
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Character")
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 8)
                    Circle().trim(from: 0, to: max(0.02, momentum.progressToNextLevel))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -1) {
                        Text("\(momentum.level)").font(.system(size: 26, weight: .bold)).monospacedDigit()
                        Text("LVL").font(.system(size: 9, weight: .bold)).tracking(0.6).opacity(0.85)
                    }
                    .foregroundStyle(Color.white)
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(momentum.levelTitle)
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
                    Text("\(momentum.pointsIntoLevel) / 500 XP to level \(momentum.level + 1)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.9))
                    if momentum.streak() > 0 {
                        Label("\(momentum.streak())-day streak", systemImage: "flame.fill")
                            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.white.opacity(0.22), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accentColor, Theme.accentColor.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Theme.accentColor.opacity(0.3), radius: 16, y: 8)
    }

    // MARK: Attributes

    private func attributesSection(_ readings: [AttributeEngine.Reading]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Attributes")
            ForEach(readings) { r in attributeRow(r) }
        }
    }

    private func attributeRow(_ r: AttributeEngine.Reading) -> some View {
        HStack(spacing: 12) {
            IconChip(icon: r.attribute.icon, tint: r.attribute.color, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.attribute.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("Lv \(r.level)").font(.system(size: 11, weight: .bold)).foregroundStyle(r.attribute.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(r.attribute.color.opacity(0.14), in: Capsule())
                    Spacer(minLength: 4)
                    Text("\(r.intoLevel)/\(r.neededForLevel)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
                BecomingBar(fraction: r.progress, color: r.attribute.color, height: 7)
                Text(r.attribute.blurb).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
        }
        .panel(padding: 14)
    }

    @ViewBuilder
    private func growthNote(_ readings: [AttributeEngine.Reading]) -> some View {
        if let strong = AttributeEngine.strongest(readings), strong.xp > 0,
           let weak = AttributeEngine.weakest(readings) {
            HStack(alignment: .top, spacing: 12) {
                IconChip(icon: "chart.line.uptrend.xyaxis", tint: Theme.accentColor, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(strong.attribute.title) is your strength right now")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("A little more \(weak.attribute.title.lowercased()) would round you out — one small block moves it.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .panel(padding: 14)
        }
    }

    private var footer: some View {
        Text("Attributes rise only from real evidence over the last 60 days — focus time, finished work, and showing up. They measure momentum, never worth.")
            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

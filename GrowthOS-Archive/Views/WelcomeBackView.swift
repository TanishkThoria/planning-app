import SwiftUI

/// The "Day Zero" antidote. Many people believe they have to wait for a fresh
/// Monday to become a new person. When someone returns after time away, Chronos
/// shows no guilt and no lost progress — just the smallest possible next step.
struct WelcomeBackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var timer: FocusTimerController
    @ObservedObject private var momentum = MomentumStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    intactCard
                    startCard
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .chronosAppearance()
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconChip(icon: "hand.wave.fill", tint: Theme.accentColor, size: 52)
            Text("Welcome back.")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("No guilt, no catching up. You don't have to wait for Monday to be the person you're becoming — you just have to take the next small step.")
                .font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything you built is still here")
                .font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 12) {
                stat("Level \(momentum.level)", momentum.levelTitle, "sparkles")
                if momentum.bestStreak() > 0 {
                    stat("\(momentum.bestStreak())-day", "best streak", "flame.fill")
                }
                if !life.activePillars.isEmpty {
                    stat("\(life.activePillars.count)", "pillars", "figure.stand")
                }
            }
        }
        .panel()
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            IconChip(icon: icon, tint: Theme.accentColor, size: 28)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your next step is simple")
                .font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.textPrimary)
            ChronosPrimaryButton("Start with 10 minutes", icon: "play.fill") {
                timer.focusMinutes = 10
                timer.start(taskID: nil, title: "Ease back in", mode: .pomodoro)
                dismiss()
                // Present the timer sheet only after this one has animated away,
                // so the two RootView sheets don't collide.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    model.focusTimerPresented = true
                }
            }
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    model.dayIntentPresented = true
                }
            } label: {
                Text("Set today's minimum instead")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentColor)
            }
            .buttonStyle(.plain)
        }
        .panel()
    }
}

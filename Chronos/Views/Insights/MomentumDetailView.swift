import SwiftUI

/// The momentum deep-dive: exactly how today's score is built, the single
/// highest-value thing left to do, every streak you're keeping, your freezes,
/// and a plain-language guide. Full transparency — momentum is never a mystery.
struct MomentumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @ObservedObject private var store = MomentumStore.shared

    private var today: Date { Date().startOfDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if let next = MomentumEngine.nextBestAction(input) { nextUpCard(next) }
                    streaksCard
                    breakdownCard
                    statsRow
                    guide
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Momentum")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .chronosAppearance()
        .onAppear { store.record(score) }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 9).frame(width: 92, height: 92)
                Circle()
                    .trim(from: 0, to: Double(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 92, height: 92)
                    .animation(.snappy, value: score)
                VStack(spacing: 0) {
                    Text("\(score)").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("today").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 13.5)).foregroundStyle(Theme.accentColor)
                    Text("Level \(store.level) · \(store.levelTitle)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("\(store.pointsIntoLevel) / 500 to level \(store.level + 1)")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.accentColor)
                            .frame(width: max(4, geo.size.width * store.progressToNextLevel))
                    }
                }
                .frame(height: 6)
            }
        }
        .panel()
    }

    // MARK: Next best action

    private func nextUpCard(_ part: MomentumEngine.Breakdown) -> some View {
        Button { boost(part.factor) } label: {
            HStack(spacing: 12) {
                IconChip(icon: part.icon, tint: Theme.accentColor, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biggest boost right now")
                        .font(.system(size: 12, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                    Text(part.tip)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.accentColor)
            }
            .padding(16)
            .background(Theme.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
                .strokeBorder(Theme.accentColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Streaks

    private var streaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Streaks")
            HStack(spacing: 10) {
                streakTile("flame.fill", "\(store.streak())", "Momentum", Theme.warning)
                streakTile("trophy.fill", "\(store.bestStreak())", "Best ever", Color(hex: 0xF2C14E))
                streakTile("timer", "\(focusStreak)", "Focus", Theme.success)
                streakTile("wand.and.stars", "\(planningStreak)", "Planning", Theme.accentColor)
            }
            if store.availableFreezes > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "snowflake").font(.system(size: 13.5)).foregroundStyle(Color(hex: 0x6FB6FF))
                    Text("\(store.availableFreezes) streak freeze\(store.availableFreezes == 1 ? "" : "s") banked — one off-day won't break your streak.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(hex: 0x6FB6FF).opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
            }
        }
        .panel()
    }

    private func streakTile(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
    }

    // MARK: Breakdown with tips

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today, point by point")
            VStack(spacing: 12) {
                ForEach(MomentumEngine.breakdown(input)) { part in
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            IconChip(icon: part.icon, tint: part.isComplete ? Theme.success : ChipPalette.color(for: part.label), size: 28)
                            Text(part.label).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(part.earned)/\(part.max)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(part.isComplete ? Theme.success : Theme.textTertiary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fill)
                                Capsule().fill(part.isComplete ? Theme.success : Theme.accentColor)
                                    .frame(width: geo.size.width * (Double(part.earned) / Double(part.max)))
                            }
                        }
                        .frame(height: 6)
                        if !part.isComplete, !part.tip.isEmpty {
                            Button { boost(part.factor) } label: {
                                HStack(spacing: 5) {
                                    Text(part.tip).font(.system(size: 12.5))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Lifetime stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile("star.fill", "\(store.perfectDays)", "Perfect days", Color(hex: 0xFFB23E))
            statTile("checkmark.seal.fill", "\(store.solidDays)", "Solid days", Color(hex: 0x3FC97A))
            statTile("calendar", "\(store.activeDays)", "Active days", Theme.accentColor)
        }
    }

    private func statTile(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 7) {
            IconChip(icon: icon, tint: tint, size: 32)
            Text(value).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Momentum rewards the real ingredients of a good day — planning, doing, focusing, habits, and reflecting — not vanity metrics. It only ever ratchets up within a day, so a morning glance never locks in a low number. Keep it above \(MomentumStore.solidThreshold) to grow your streak; freezes protect the odd off-day.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func boost(_ factor: MomentumEngine.Factor) {
        let action: () -> Void
        switch factor {
        case .plan: action = { model.screen = .today; model.morningPlanningPresented = true }
        case .complete: action = { model.screen = .tasks }
        case .focus: action = { model.startFocus(taskID: nil, title: "Focus") }
        case .habits: action = { model.screen = .grow }
        case .frog: action = { model.screen = .today }
        }
        model.pendingCommandBarAction = action
        dismiss()
    }

    // MARK: Data

    private var input: MomentumEngine.Input {
        let blocks = service.blocks(on: today, hiddenCalendars: model.hiddenCalendarIDs).filter { !$0.isAllDay }
        let habitsDue = life.activeHabits.filter { $0.isDue(on: today) }
        let frog = model.frogTaskID.flatMap { service.task(withID: $0) }
        return MomentumEngine.Input(
            plannedBlocks: blocks.count,
            tasksCompletedToday: service.tasks.filter { $0.isCompleted && ($0.completionDate?.isToday ?? false) }.count,
            focusMinutesToday: focusLog.sessions(on: today).reduce(0) { $0 + $1.actualMinutes },
            habitsDue: habitsDue.count,
            habitsDone: habitsDue.filter { life.isDone($0, on: today) }.count,
            frogEaten: frog?.isCompleted ?? false
        )
    }

    private var score: Int { MomentumEngine.score(input) }
    private var scoreColor: Color {
        score >= 70 ? Theme.success : (score >= 40 ? Theme.accentColor : Theme.warning)
    }

    private var focusStreak: Int {
        MomentumStore.streak(endingToday: { day in
            focusLog.sessions(on: day).reduce(0) { $0 + $1.actualMinutes } > 0
        })
    }
    private var planningStreak: Int {
        MomentumStore.streak(endingToday: { day in
            !service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs).filter { !$0.isAllDay }.isEmpty
        })
    }
}

import SwiftUI

/// The momentum hero: today's 0–100 score as a ring, the level + streak, a
/// two-week trend sparkline, and an expandable breakdown of exactly how each
/// point was earned (so it's motivating, never mysterious).
struct MomentumCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @ObservedObject private var store = MomentumStore.shared

    @State private var expanded = false

    private var today: Date { Date().startOfDay }

    private var input: MomentumEngine.Input {
        let blocks = service.blocks(on: today, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        IconChip(icon: "bolt.fill", tint: Color(hex: 0xFFB23E), size: 24)
                        Text("Lv \(store.level) · \(store.levelTitle)")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if store.streak() > 0 {
                        Label("\(store.streak())-day momentum streak", systemImage: "flame.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    } else {
                        Text("Build a streak — keep the score up daily.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    }
                    levelBar
                }
                Spacer()
                sparkline
            }

            if let next = MomentumEngine.nextBestAction(input) {
                Button { model.momentumDetailPresented = true } label: {
                    HStack(spacing: 9) {
                        IconChip(icon: next.icon, tint: Theme.accentColor, size: 26)
                        Text(next.tip).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Theme.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "Hide breakdown" : "How's this scored?")
                            .font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { model.momentumDetailPresented = true } label: {
                    Text("Streaks & tips →").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(spacing: 6) {
                    ForEach(MomentumEngine.breakdown(input)) { part in
                        HStack(spacing: 9) {
                            Image(systemName: part.icon)
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                                .frame(width: 16)
                            Text(part.label).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.fill)
                                    Capsule().fill(part.earned >= part.max ? Theme.success : Theme.accentColor)
                                        .frame(width: geo.size.width * (Double(part.earned) / Double(part.max)))
                                }
                            }
                            .frame(width: 70, height: 5)
                            Text("\(part.earned)/\(part.max)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .panel()
        .onAppear { store.record(score) }
        .onChange(of: score) { _, new in store.record(new) }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.fill, lineWidth: 7).frame(width: 60, height: 60)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .animation(.snappy, value: score)
            Text("\(score)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var scoreColor: Color {
        score >= 70 ? Theme.success : (score >= 40 ? Theme.accentColor : Theme.warning)
    }

    private var levelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(Theme.accentColor.opacity(0.7))
                    .frame(width: max(3, geo.size.width * store.progressToNextLevel))
            }
        }
        .frame(width: 120, height: 4)
        .padding(.top, 1)
    }

    private var sparkline: some View {
        let trend = store.trend(days: 14)
        let peak = max(trend.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(trend.enumerated()), id: \.offset) { idx, value in
                Capsule()
                    .fill(idx == trend.count - 1 ? Theme.accentColor : Theme.accentColor.opacity(0.35))
                    .frame(width: 3, height: max(3, CGFloat(value) / CGFloat(peak) * 34))
            }
        }
        .frame(height: 34)
    }
}

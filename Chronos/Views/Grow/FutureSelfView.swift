import SwiftUI

/// The spine of Chronos 2.0: the person the user is becoming, measured in
/// evidence rather than goals. Identity pillars each show a live "becoming"
/// reading drawn from the real things the user did; a Future Self definition and
/// a 1/5/10-year vision timeline keep today connected to the long arc.
///
/// Deliberately framed as momentum, never worth — the copy says so out loud.
struct FutureSelfView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog

    @State private var expanded: UUID?
    @State private var editingFutureSelf = false
    @State private var evidencePillarID: UUID?
    @State private var evidenceText = ""

    private let windowDays = 14
    private var today: Date { Date().startOfDay }

    var body: some View {
        // Compute the (relatively expensive) evidence readings ONCE per render
        // and hand them to the subviews that need them.
        let readings = computedReadings
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(readings)
                    if life.activePillars.isEmpty {
                        seedCard
                    } else {
                        pillarsSection(readings)
                    }
                    futureSelfSection
                    visionsSection
                    if !life.futureSelf.dailyActions.isEmpty { todayActionsSection }
                    footerNote
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Future Self")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { model.pillarEditor = PillarEditContext(pillar: IdentityPillar(), isNew: true) } label: {
                            Label("New Pillar", systemImage: "plus")
                        }
                        Button { editingFutureSelf = true } label: {
                            Label("Edit Future Self", systemImage: "person.fill.viewfinder")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .chronosAppearance()
        .sheet(isPresented: $editingFutureSelf) { FutureSelfEditorView() }
        .sheet(item: $model.pillarEditor) { context in
            IdentityPillarEditorView(context: context)
        }
        .alert("Note evidence", isPresented: Binding(
            get: { evidencePillarID != nil },
            set: { if !$0 { evidencePillarID = nil; evidenceText = "" } }
        )) {
            TextField("What did you do?", text: $evidenceText)
            Button("Add") {
                if let pid = evidencePillarID {
                    life.addEvidence(pillarID: pid, text: evidenceText, source: .manual, strength: 2)
                    Haptics.success()
                }
                evidencePillarID = nil; evidenceText = ""
            }
            Button("Cancel", role: .cancel) { evidencePillarID = nil; evidenceText = "" }
        } message: {
            Text("A small proof that you're becoming this person.")
        }
    }

    // MARK: Hero

    private func hero(_ readings: [PillarReading]) -> some View {
        let overall = readings.isEmpty ? 0 : readings.map(\.score).reduce(0, +) / Double(readings.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconChip(icon: "figure.stand", tint: Theme.accentColor, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You are becoming")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(life.futureSelf.isDefined ? life.futureSelf.name : "The person your future self imagines")
                        .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            if !life.activePillars.isEmpty {
                BecomingBar(fraction: overall, color: Theme.accentColor, height: 10)
                Text("\(Int((overall * 100).rounded()))% — a measure of momentum over the last \(windowDays) days, not a measure of your worth.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accentColor.opacity(0.16), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var seedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name the person you're building")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("Pillars are the facets of who you want to become — Health, Career, Discipline. Each one fills with evidence from the real things you do.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChronosPrimaryButton("Guided setup", icon: "wand.and.stars") {
                dismiss()
                model.afterDismiss { model.identitySetupPresented = true }
            }
            Button {
                withAnimation(.snappy) { life.seedDefaultPillars() }
                Haptics.success()
            } label: {
                Text("Or start with 8 suggested pillars")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
            }
            .buttonStyle(.plain)
            Button { model.pillarEditor = PillarEditContext(pillar: IdentityPillar(), isNew: true) } label: {
                Text("Or create my own")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .panel()
    }

    // MARK: Pillars

    private func pillarsSection(_ readings: [PillarReading]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Identity pillars", trailing: "\(life.activePillars.count)")
                Spacer(minLength: 8)
                Button { model.pillarEditor = PillarEditContext(pillar: IdentityPillar(), isNew: true) } label: {
                    Image(systemName: "plus").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            ForEach(readings) { reading in pillarCard(reading) }
        }
    }

    private func pillarCard(_ reading: PillarReading) -> some View {
        let pillar = reading.pillar
        let isOpen = expanded == pillar.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded = isOpen ? nil : pillar.id }
            } label: {
                HStack(spacing: 12) {
                    IconChip(icon: pillar.iconName, tint: pillar.color, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(pillar.name.isEmpty ? "Pillar" : pillar.name)
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            trendPill(reading.trend)
                        }
                        BecomingBar(fraction: reading.score, color: pillar.color, height: 7)
                    }
                    Text("\(Int((reading.score * 100).rounded()))%")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(pillar.color)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                if !pillar.detail.isEmpty {
                    Text(pillar.detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                if reading.recent.isEmpty {
                    Text("No evidence yet in the last \(windowDays) days. Do one small thing — then note it here.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Recent evidence").font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                    ForEach(reading.recent) { ev in evidenceRow(ev) }
                }
                HStack(spacing: 10) {
                    Button { evidencePillarID = pillar.id } label: {
                        Label("Note evidence", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(pillar.color)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { model.pillarEditor = PillarEditContext(pillar: pillar, isNew: false) } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel(padding: 14)
        .contextMenu {
            Button { model.pillarEditor = PillarEditContext(pillar: pillar, isNew: false) } label: {
                Label("Edit pillar", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { life.deletePillar(pillar.id) }
            } label: { Label("Delete pillar", systemImage: "trash") }
        }
    }

    private func evidenceRow(_ ev: IdentityEvidence) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ev.source.icon).font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary).frame(width: 18)
            Text(ev.text).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).lineLimit(2)
            Spacer(minLength: 4)
            Text(Fmt.relativeDay(ev.date)).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            if ev.source == .manual || ev.source == .reflection {
                Button { life.deleteEvidence(ev.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trendPill(_ trend: EvidenceTrend) -> some View {
        Label(trend.label, systemImage: trend.icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(trend == .quiet ? Theme.textTertiary : Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.fill, in: Capsule())
    }

    // MARK: Future self identity

    private var futureSelfSection: some View {
        let fs = life.futureSelf
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "The person I'm becoming")
            if fs.isDefined {
                VStack(alignment: .leading, spacing: 10) {
                    if !fs.name.isEmpty {
                        Text(fs.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    }
                    if !fs.summary.isEmpty {
                        Text(fs.summary).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !fs.attributes.isEmpty {
                        FlowChips(items: fs.attributes, tint: Theme.accentColor)
                    }
                    Button { editingFutureSelf = true } label: {
                        Text("Edit").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .panel()
            } else {
                Button { editingFutureSelf = true } label: {
                    HStack(spacing: 12) {
                        IconChip(icon: "person.fill.viewfinder", tint: Theme.accentColor, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Define your future self").font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Give this person a name and a few attributes").font(.system(size: 12.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .panel(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Visions

    private var visionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "The long arc")
            ForEach(VisionHorizon.allCases) { horizon in visionCard(horizon) }
        }
    }

    private func visionCard(_ horizon: VisionHorizon) -> some View {
        let text = visionText(horizon)
        return Button { editingFutureSelf = true } label: {
            HStack(alignment: .top, spacing: 12) {
                IconChip(icon: horizon.icon, tint: Theme.accentColor, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(horizon.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(text.isEmpty ? horizon.prompt : text)
                        .font(.system(size: 13)).foregroundStyle(text.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .panel(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func visionText(_ h: VisionHorizon) -> String {
        switch h {
        case .oneYear: return life.futureSelf.visionOneYear
        case .fiveYear: return life.futureSelf.visionFiveYear
        case .tenYear: return life.futureSelf.visionTenYear
        }
    }

    // MARK: Today's identity actions

    private var todayActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What that person does today")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(life.futureSelf.dailyActions.enumerated()), id: \.offset) { _, action in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 12))
                            .foregroundStyle(Theme.accentColor)
                        Text(action).font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .panel()
        }
    }

    private var footerNote: some View {
        Text("Evidence measures who you're becoming — it never measures who you are. A quiet pillar isn't a failure; it's just the next place to put a small win.")
            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: Derived data

    private var computedReadings: [PillarReading] {
        EvidenceEngine.readings(
            pillars: life.activePillars, life: life, focus: focusLog,
            taskEvidence: taskEvidence, goalProgress: goalProgress, windowDays: windowDays)
    }

    private var taskEvidence: [TaskEvidence] {
        let since = today.adding(days: -(windowDays - 1))
        return service.tasks.compactMap { t in
            guard t.isCompleted, let d = t.completionDate, d >= since else { return nil }
            return TaskEvidence(date: d, category: TagStore.shared.category(for: t), title: t.title)
        }
    }

    private var goalProgress: [UUID: Double] {
        var out: [UUID: Double] = [:]
        for g in life.activeGoals { out[g.id] = goalFraction(g) }
        return out
    }

    private func goalFraction(_ goal: Goal) -> Double {
        switch goal.kind {
        case .time:
            let target = goal.weeklyHoursTarget * 60
            return target <= 0 ? 0 : min(1, Double(weekMinutes(goal.linkedCalendarID)) / target)
        case .milestone:
            return goal.milestoneProgress
        case .habitLink:
            guard let hid = goal.linkedHabitID, let h = life.habits.first(where: { $0.id == hid }) else { return 0 }
            return min(1, Double(life.completionCount(h, inLast: 7)) / 7)
        }
    }

    private func weekMinutes(_ calendarID: String?) -> Int {
        let start = today.startOfWeek
        return (0..<7).reduce(0) { acc, offset in
            let day = start.adding(days: offset)
            return acc + service.blocks(on: day)
                .filter { !$0.isAllDay && (calendarID == nil || $0.calendarID == calendarID) }
                .compactMap { $0.clamped(to: day) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        }
    }
}

// MARK: - Small shared pieces

/// A thin, rounded "becoming" progress bar.
struct BecomingBar: View {
    let fraction: Double
    var color: Color = Theme.accentColor
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// A simple wrapping set of tinted chips (for attributes).
struct FlowChips: View {
    let items: [String]
    var tint: Color = Theme.accentColor
    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
    }
}

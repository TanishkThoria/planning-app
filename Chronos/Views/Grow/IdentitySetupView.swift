import SwiftUI

/// The identity-first setup — the emotionally compelling on-ramp. Not "what are
/// your tasks" but "who do you want to become?" Picks archetypes (which seed
/// pillars), captures where life is now (the radar), the big ten-year dream, and
/// how the user procrastinates (so the coach can name it). Ends at "this is where
/// your story starts."
struct IdentitySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    @State private var step = 0
    @State private var picked: Set<String> = []
    @State private var ratings: [LifeArea: Int] = [:]
    @State private var dream = ""
    @State private var tendencies: Set<ProcrastinationStyle> = []

    private let totalSteps = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(Theme.accentColor)
                    .padding(.horizontal, Theme.Metric.screen).padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case 0: identityStep
                        case 1: satisfactionStep
                        case 2: dreamStep
                        case 3: tendenciesStep
                        default: finishStep
                        }
                    }
                    .padding(Theme.Metric.screen)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .background(Theme.bg)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { finish() } }
            }
        }
        .chronosAppearance()
        .onAppear {
            if ratings.isEmpty {
                for area in LifeArea.allCases { ratings[area] = 5 }
            }
            dream = life.bigDream
            tendencies = Set(life.procrastinationStyleValues)
        }
    }

    // MARK: Steps

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Who do you want to become?",
                       "Pick the identities you're building toward. Each one sets up the pillars that track it.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(IdentityArchetype.all) { arch in
                    let on = picked.contains(arch.id)
                    Button {
                        if on { picked.remove(arch.id) } else { picked.insert(arch.id) }
                        Haptics.light()
                    } label: {
                        VStack(spacing: 8) {
                            IconChip(icon: arch.icon, tint: arch.color, size: 40)
                            Text(arch.title).font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(on ? arch.color : Theme.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(on ? arch.color.opacity(0.12) : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(on ? arch.color.opacity(0.5) : Theme.hairline, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var satisfactionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Where are you now?",
                       "An honest baseline — no judgement. You'll watch these move over time.")
            VStack(spacing: 14) {
                ForEach(LifeArea.allCases) { area in
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: area.icon).font(.system(size: 13)).foregroundStyle(Theme.accentColor)
                                .frame(width: 20)
                            Text(area.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(ratings[area] ?? 5)").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.accentColor).monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(ratings[area] ?? 5) },
                            set: { ratings[area] = Int($0.rounded()) }
                        ), in: 0...10, step: 1)
                    }
                }
            }
            .panel()
        }
    }

    private var dreamStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Your big dream",
                       "If your life went unbelievably well over the next ten years, what would it look like? Write freely — you'll see this again on your yearly review.")
            TextField("In ten years…", text: $dream, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(5...12)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private var tendenciesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("How do you procrastinate?",
                       "When you avoid something, what do you reach for? Chronos uses this to name the pattern back to you — gently.")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(ProcrastinationStyle.allCases) { s in
                    let on = tendencies.contains(s)
                    Button {
                        if on { tendencies.remove(s) } else { tendencies.insert(s) }
                        Haptics.light()
                    } label: {
                        Label(s.title, systemImage: s.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? Color.white : Theme.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(on ? Theme.accentColor : Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            IconChip(icon: "flag.fill", tint: Theme.accentColor, size: 52)
            Text("This is where your story starts.")
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Chronos will fill your pillars with evidence as you live — one focused block, one kept habit, one finished thing at a time. You don't have to be perfect. You just have to keep showing up.")
                .font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !picked.isEmpty {
                let names = picked.compactMap { id in IdentityArchetype.all.first { $0.id == id }?.title }
                FlowChips(items: names, tint: Theme.accentColor)
            }
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer nav

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { withAnimation(.snappy) { step -= 1 } } label: {
                    Text("Back").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            ChronosPrimaryButton(step == totalSteps - 1 ? "Start my story" : "Continue",
                                 icon: step == totalSteps - 1 ? "sparkles" : nil) {
                if step < totalSteps - 1 { withAnimation(.snappy) { step += 1 } } else { finish() }
            }
        }
        .padding(.horizontal, Theme.Metric.screen)
        .padding(.vertical, 12)
    }

    // MARK: Persist

    private func finish() {
        // Seed pillars from the chosen archetypes (dedupe by name).
        var wanted: [String] = []
        for id in picked {
            if let arch = IdentityArchetype.all.first(where: { $0.id == id }) {
                for name in arch.pillars where !wanted.contains(name) { wanted.append(name) }
            }
        }
        for name in wanted where !life.identityPillars.contains(where: { $0.name == name }) {
            if let preset = IdentityPillar.presets.first(where: { $0.name == name }) {
                life.upsert(preset)
            }
        }
        // Satisfaction radar snapshot.
        if !ratings.isEmpty { life.recordSatisfaction(ratings) }
        // Big dream → also the ten-year vision.
        let trimmedDream = dream.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDream.isEmpty {
            life.bigDream = trimmedDream
            var fs = life.futureSelf
            if fs.visionTenYear.isEmpty { fs.visionTenYear = trimmedDream; life.updateFutureSelf(fs) }
        }
        // Procrastination tendencies.
        life.setProcrastinationStyles(Array(tendencies))
        // A start memory.
        life.recordAutoEvent(key: "chronos-start", title: "Started your Chronos journey",
                             kind: .start, emoji: "🌱")
        Haptics.success()
        dismiss()
    }
}

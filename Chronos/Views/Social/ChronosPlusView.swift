import SwiftUI

/// The Chronos+ hub: the single place where the paid-account features are
/// explained, toggled, and (when available) used. Everything here degrades
/// gracefully — on the free account it shows exactly what will light up and how
/// to switch it on, without a single nag or dead end.
struct ChronosPlusView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var paid = PaidFeatures.shared
    @ObservedObject private var cloud = CloudSyncService.shared

    @AppStorage(Prefs.chronosPlusEnabled) private var masterEnabled = false
    @AppStorage(Prefs.cloudSyncEnabled) private var cloudSyncEnabled = true
    @AppStorage(Prefs.socialEnabled) private var socialEnabled = true
    @AppStorage(Prefs.liveWidgetsEnabled) private var liveWidgetsEnabled = true

    @State private var leaderboardPresented = false
    @State private var friendsPresented = false
    @State private var duelsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if paid.anyCapabilityEntitled {
                        masterCard
                    } else {
                        turnOnGuide
                    }
                    capabilitiesSection
                    exploreSection
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Chronos+")
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
        .onAppear { paid.refresh() }
        .sheet(isPresented: $leaderboardPresented) { LeaderboardView() }
        .sheet(isPresented: $friendsPresented) { FriendsView() }
        .sheet(isPresented: $duelsPresented) { FriendChallengesView() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Text("Chronos+")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Sync every device, race friends on the leaderboard, and see what the people you plan with are focusing on — all powered by your own iCloud, still zero-server and private.")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.accentColor.opacity(0.18), Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: Master toggle (entitled builds)

    /// Only mention iCloud sign-in when the cloud features are actually part of
    /// this build; otherwise keep it about the switch itself.
    private var masterSubtitle: String {
        guard paid.isEntitled(.cloudSync) else { return "Enable your Chronos+ features." }
        return paid.iCloud == .available
            ? "iCloud is signed in on this device."
            : "Signed out of iCloud — sync features wait until you sign in."
    }
    private var masterSubtitleWarns: Bool {
        paid.isEntitled(.cloudSync) && paid.iCloud != .available
    }

    private var masterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $masterEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on Chronos+")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(masterSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(masterSubtitleWarns ? Theme.warning : Theme.textTertiary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: masterEnabled) { _, on in
                paid.refresh()
                if on { Task { await cloud.syncNow() } }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: Turn-on guide (free builds)

    private var turnOnGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ready when you are", systemImage: "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
            Text("Every Chronos+ feature is already built in. They switch on the moment your app is signed with a paid Apple Developer account — and they're independent, so you can turn on the transfer-safe ones first. No new code — just capabilities.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                guideStep(1, "In Xcode, select the Chronos target → Signing & Capabilities.")
                guideStep(2, "Ship now: add App Groups (group.app.chronos.planner) for Live Widgets, and Game Center + the CHRONOS_GAMECENTER flag for leaderboards.")
                guideStep(3, "After transfer: add iCloud (CloudKit + container) + the CHRONOS_CLOUD flag for Sync & Friends. (CHRONOS_PLUS enables everything at once.)")
                guideStep(4, "Reopen this screen — the master switch appears and everything you enabled turns on with one tap.")
            }
            .padding(12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Full walkthrough: docs/CHRONOS_PLUS_SETUP.md")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

            // Let the user pre-arm the switch now so it's already on at upgrade.
            Toggle(isOn: $masterEnabled) {
                Text("Pre-enable Chronos+ (activates automatically once entitled)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func guideStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 20, height: 20)
                .background(Theme.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Per-capability list

    /// Only the capabilities this build actually ships — so a pre-transfer
    /// build (Game Center + widgets) doesn't list iCloud/Friends it can't run.
    private var entitledCapabilities: [PaidCapability] {
        PaidCapability.allCases.filter { paid.isEntitled($0) }
    }

    private func toggleBinding(for capability: PaidCapability) -> Binding<Bool> {
        switch capability {
        case .cloudSync: return $cloudSyncEnabled
        case .leaderboards, .friends: return $socialEnabled
        case .liveWidgets: return $liveWidgetsEnabled
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Features")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(entitledCapabilities.enumerated()), id: \.element.id) { index, capability in
                    if index > 0 { divider }
                    capabilityRow(capability, toggle: toggleBinding(for: capability))
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 46)
    }

    private func capabilityRow(_ capability: PaidCapability, toggle: Binding<Bool>) -> some View {
        let ready = paid.isReady(capability)
        return HStack(spacing: 12) {
            Image(systemName: capability.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ready ? Theme.accentColor : Theme.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(ready ? capability.subtitle : paid.status(for: capability))
                    .font(.system(size: 12.5))
                    .foregroundStyle(ready ? Theme.textTertiary : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if paid.isEntitled(capability) {
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!masterEnabled)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: Explore (leaderboard + friends)

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Explore")
                .padding(.horizontal, 4)
            VStack(spacing: 10) {
                exploreButton(
                    icon: "trophy.fill", title: "Leaderboard",
                    subtitle: "Weekly focus & all-time momentum"
                ) { leaderboardPresented = true }
                exploreButton(
                    icon: "person.2.fill", title: "Friends",
                    subtitle: "Presence & your friend code"
                ) { friendsPresented = true }
                exploreButton(
                    icon: "flag.2.crossed.fill", title: "Duels",
                    subtitle: "Challenge a friend head-to-head"
                ) { duelsPresented = true }
            }
        }
    }

    private func exploreButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

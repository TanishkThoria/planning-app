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
        .preferredColorScheme(.dark)
        .onAppear { paid.refresh() }
        .sheet(isPresented: $leaderboardPresented) { LeaderboardView() }
        .sheet(isPresented: $friendsPresented) { FriendsView() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Chronos+")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Sync every device, race friends on the leaderboard, and see what the people you plan with are focusing on — all powered by your own iCloud, still zero-server and private.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Theme.surface],
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

    private var masterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $masterEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on Chronos+")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(paid.iCloud == .available
                         ? "iCloud is signed in on this device."
                         : "Signed out of iCloud — sync features wait until you sign in.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(paid.iCloud == .available ? Theme.textTertiary : Theme.warning)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Every Chronos+ feature is already built in. They switch on the moment your app is signed with a paid Apple Developer account, which adds the iCloud, App Group and Game Center capabilities. No new code — just capabilities.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                guideStep(1, "In Xcode, select the Chronos target → Signing & Capabilities.")
                guideStep(2, "Add iCloud (CloudKit + the container), App Groups (group.app.chronos.planner), and Game Center.")
                guideStep(3, "Add CHRONOS_PLUS to Active Compilation Conditions (the safety interlock).")
                guideStep(4, "Reopen this screen — the master switch appears and everything turns on with one tap.")
            }
            .padding(12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Full walkthrough: docs/CHRONOS_PLUS_SETUP.md")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

            // Let the user pre-arm the switch now so it's already on at upgrade.
            Toggle(isOn: $masterEnabled) {
                Text("Pre-enable Chronos+ (activates automatically once entitled)")
                    .font(.system(size: 12.5, weight: .medium))
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
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Per-capability list

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Features")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                capabilityRow(.cloudSync, toggle: $cloudSyncEnabled)
                divider
                capabilityRow(.leaderboards, toggle: $socialEnabled)
                divider
                capabilityRow(.friends, toggle: $socialEnabled)
                divider
                capabilityRow(.liveWidgets, toggle: $liveWidgetsEnabled)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ready ? Color.accentColor : Theme.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(ready ? capability.subtitle : paid.status(for: capability))
                    .font(.system(size: 11))
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
                    .font(.system(size: 12))
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
            }
        }
    }

    private func exploreButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Message / Call / FaceTime a friend to set up a real study session. Chronos
/// only opens the relevant Apple app with the handle the friend chose to share
/// — it never places the call or sends anything itself.
enum ContactLink {
    case message, call, facetime, facetimeAudio
    var icon: String {
        switch self {
        case .message: return "message.fill"
        case .call: return "phone.fill"
        case .facetime: return "video.fill"
        case .facetimeAudio: return "phone.badge.waveform.fill"
        }
    }
    var label: String {
        switch self {
        case .message: return "Message"
        case .call: return "Call"
        case .facetime: return "FaceTime"
        case .facetimeAudio: return "Audio"
        }
    }
    func url(for handle: String) -> URL? {
        let h = handle.trimmingCharacters(in: .whitespaces)
        let encoded = h.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? h
        switch self {
        case .message: return URL(string: "sms:\(encoded)")
        case .call: return URL(string: "tel:\(encoded)")
        case .facetime: return URL(string: "facetime:\(encoded)")
        case .facetimeAudio: return URL(string: "facetime-audio:\(encoded)")
        }
    }
    /// tel: only works for phone numbers, not Apple ID emails.
    func applies(to handle: String) -> Bool {
        let isEmail = handle.contains("@")
        return self == .call ? !isEmail : true
    }
}

/// The social hub: your live status, the friends you plan with, an activity
/// feed, and the cheers they send you. Backed by your own iCloud (public
/// CloudKit), so it stays server-free. Locked, but never a dead end, on the
/// free account.
struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var paid = PaidFeatures.shared

    @AppStorage(Prefs.socialDisplayName) private var displayName = "Me"
    @AppStorage(Prefs.socialStatusEmoji) private var statusEmoji = ""
    @AppStorage(Prefs.socialStatusText) private var statusText = ""

    enum Tab: String, CaseIterable, Identifiable { case friends, activity; var id: String { rawValue } }
    @State private var tab: Tab = .friends
    @State private var newCode = ""
    @State private var copied = false
    @State private var profile: FriendStatus?
    @State private var editingStatus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    youCard
                    tabPicker
                    if tab == .friends { friendsTab } else { activityTab }
                    if !paid.isEntitled(.friends) { lockedNote }
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Friends")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .task { if paid.isReady(.friends) { await social.refreshFriends() } }
        .sheet(item: $profile) { FriendProfileSheet(status: $0) }
        .sheet(isPresented: $editingStatus) { StatusEditor() }
    }

    // MARK: You

    private var youCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Avatar(name: displayName, emoji: statusEmoji, size: 56, ring: true)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Your name", text: $displayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Button { editingStatus = true } label: {
                        HStack(spacing: 5) {
                            Text(statusLine)
                                .font(.system(size: 12.5))
                                .foregroundStyle(statusText.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                                .lineLimit(1)
                            Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Divider().overlay(Theme.hairline)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR CODE")
                        .font(.system(size: 9.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    Text(social.myFriendCode)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Button { copyCode() } label: {
                    Label(copied ? "Copied" : "Share", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: Theme.cardShadow, radius: 10, y: 4)
    }

    private var statusLine: String {
        if statusText.isEmpty && statusEmoji.isEmpty { return "Set a status" }
        return "\(statusEmoji) \(statusText)".trimmingCharacters(in: .whitespaces)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text("Friends").tag(Tab.friends)
            Text("Activity").tag(Tab.activity)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Friends tab

    @ViewBuilder
    private var friendsTab: some View {
        addFriendField
        if social.friendCodes.isEmpty {
            EmptyStateView(
                icon: "person.2",
                title: "No friends yet",
                message: "Share your code, then add a friend's to see what they're focusing on and race the leaderboard."
            )
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 10) {
                ForEach(social.friendCodes, id: \.self) { code in
                    friendCard(code: code)
                }
            }
        }
    }

    private var addFriendField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            TextField("Add a friend's code", text: $newCode)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
            Button {
                social.addFriend(code: newCode); newCode = ""
            } label: {
                Text("Add").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(newCode.isEmpty ? Theme.textTertiary : Color.accentColor)
            }
            .buttonStyle(.plain).disabled(newCode.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func friendCard(code: String) -> some View {
        let status = social.friends.first { $0.presence.code == code }
        return Button { if let status { profile = status } } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: status?.presence.displayName ?? code, emoji: status?.presence.statusEmoji ?? "", size: 44)
                    if status?.isLive == true {
                        Circle().fill(Theme.success).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(status?.presence.displayName ?? code)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle(for: status))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if let status {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("\(status.presence.streakDays)", systemImage: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                        Text(Fmt.duration(minutes: status.presence.weeklyFocus))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Activity tab

    @ViewBuilder
    private var activityTab: some View {
        if !social.receivedCheers.isEmpty {
            SectionHeader(title: "Cheers for you").padding(.horizontal, 2)
            VStack(spacing: 8) {
                ForEach(social.receivedCheers.prefix(8)) { cheer in
                    HStack(spacing: 12) {
                        Text(cheer.emoji).font(.system(size: 22))
                        Text("\(cheer.fromName) cheered you on")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(Fmt.relativeShort(cheer.date))
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
                }
            }
        }
        let moments = social.activityMoments()
        SectionHeader(title: "Activity").padding(.horizontal, 2).padding(.top, social.receivedCheers.isEmpty ? 0 : 6)
        if moments.isEmpty {
            EmptyStateView(icon: "waveform.path.ecg", title: "Quiet for now",
                           message: "When your friends plan, focus, or hit a streak, it shows up here.")
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                ForEach(moments) { moment in
                    HStack(spacing: 12) {
                        Image(systemName: moment.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: moment.tint))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: moment.tint).opacity(0.15), in: Circle())
                        (Text(moment.name).font(.system(size: 13, weight: .semibold)) + Text(" \(moment.text)").font(.system(size: 13)))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
        }
    }

    private func subtitle(for status: FriendStatus?) -> String {
        guard let status else {
            return paid.isReady(.friends) ? "Waiting for their next update…" : "Turn on Chronos+ to see status"
        }
        let p = status.presence
        if !p.statusText.isEmpty { return "\(p.statusEmoji) \(p.statusText)".trimmingCharacters(in: .whitespaces) }
        if status.isStale { return "\(p.busy.label) · last seen a while ago" }
        if let block = p.currentBlockTitle, !block.isEmpty { return "\(p.busy.label) · \(block)" }
        return p.busy.label
    }

    private var lockedNote: some View {
        Text("Friends presence turns on with Chronos+ (uses your iCloud). Your code, name, status, and friends list are saved and ready now.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = social.myFriendCode
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(social.myFriendCode, forType: .string)
        #endif
        Haptics.success()
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.snappy) { copied = false }
        }
    }
}

// MARK: - Status editor

private struct StatusEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.socialStatusEmoji) private var emoji = ""
    @AppStorage(Prefs.socialStatusText) private var text = ""
    @AppStorage(Prefs.sharePresence) private var sharePresence = true
    @AppStorage(Prefs.socialContactHandle) private var contactHandle = ""

    private let presets = ["🎯", "🔥", "📚", "💻", "☕️", "🧠", "😴", "🏃", "🎧", "✅"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EMOJI").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Theme.textTertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                            ForEach(presets, id: \.self) { e in
                                Button { emoji = (emoji == e ? "" : e); Haptics.light() } label: {
                                    Text(e).font(.system(size: 26))
                                        .frame(width: 48, height: 48)
                                        .background(emoji == e ? Color.accentColor.opacity(0.18) : Theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(emoji == e ? Color.accentColor : Theme.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STATUS").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Theme.textTertiary)
                        TextField("Deep work till 5…", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REACHABLE AT (OPTIONAL)").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Theme.textTertiary)
                        TextField("Phone or Apple ID email", text: $contactHandle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            #endif
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                        Text("Shared with friends so they can Message or FaceTime you to set up a study session. Leave blank to keep it private.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle(isOn: $sharePresence) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share my live status").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Let friends see what you're focusing on and your streak.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .padding(20)
                .frame(maxWidth: 480)
            }
            .background(Theme.bg)
            .navigationTitle("Your status")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .chronosAppearance()
    }
}

// MARK: - Friend profile

private struct FriendProfileSheet: View {
    let status: FriendStatus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var social = SocialService.shared
    @State private var cheered = false

    private let cheerEmojis = ["👏", "🔥", "💪", "🎯", "🙌"]
    private var handle: String { status.presence.contactHandle.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Avatar(name: status.presence.displayName, emoji: status.presence.statusEmoji, size: 72)
                        Text(status.presence.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(headline)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    if !handle.isEmpty { contactRow }

                    HStack(spacing: 10) {
                        stat("flame.fill", "\(status.presence.streakDays)d", "Streak", Theme.warning)
                        stat("timer", Fmt.duration(minutes: status.presence.weeklyFocus), "This week", Theme.success)
                        stat("bolt.fill", "\(status.presence.momentum)", "Momentum", Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SEND A CHEER").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 10) {
                            ForEach(cheerEmojis, id: \.self) { e in
                                Button {
                                    social.sendCheer(to: status.presence.code, emoji: e)
                                    Haptics.success()
                                    withAnimation(.snappy) { cheered = true }
                                } label: {
                                    Text(e).font(.system(size: 26))
                                        .frame(width: 46, height: 46)
                                        .background(Theme.surface, in: Circle())
                                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if cheered {
                            Text("Cheer sent! 🎉").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.success)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))

                    Button(role: .destructive) {
                        social.removeFriend(code: status.presence.code); dismiss()
                    } label: {
                        Text("Remove friend").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .frame(maxWidth: 440)
            }
            .background(Theme.bg)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .chronosAppearance()
    }

    private var headline: String {
        let p = status.presence
        if !p.statusText.isEmpty { return "\(p.statusEmoji) \(p.statusText)".trimmingCharacters(in: .whitespaces) }
        if let block = p.currentBlockTitle, !block.isEmpty { return "\(p.busy.label) · \(block)" }
        return "\(p.levelTitle) · \(p.busy.label)"
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Message / Call / FaceTime — opens Apple's apps so you two can plan a real
    /// session. Chronos never sends or dials anything itself.
    private var contactRow: some View {
        HStack(spacing: 10) {
            ForEach([ContactLink.message, .call, .facetime], id: \.icon) { link in
                if link.applies(to: handle) {
                    Button {
                        if let url = link.url(for: handle) { openURL(url) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: link.icon).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(link.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Friends presence: share a short code, add the people you plan with, and see
/// what everyone's focusing on right now. Backed by your own iCloud (public
/// CloudKit), so it stays server-free. Locked, but never a dead end, on the
/// free account.
struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var paid = PaidFeatures.shared

    @AppStorage(Prefs.socialDisplayName) private var displayName = "Me"
    @State private var newCode = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    addFriendCard
                    friendsList
                    if !paid.isEntitled(.friends) { lockedNote }
                }
                .padding(18)
                .frame(maxWidth: 520, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Friends")
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
        .task {
            if paid.isReady(.friends) { await social.refreshFriends() }
        }
    }

    // MARK: Your identity + code

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your code")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Theme.textTertiary)
            HStack {
                Text(social.myFriendCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    copyCode()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Theme.hairline)
            HStack {
                Text("Display name")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("Name", text: $displayName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: 180)
            }
            Text("Share your code with friends so they can follow your focus. They add it below; you add theirs.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: Add a friend

    private var addFriendCard: some View {
        HStack(spacing: 10) {
            TextField("Add a friend's code", text: $newCode)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
            Button {
                social.addFriend(code: newCode)
                newCode = ""
            } label: {
                Text("Add")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(newCode.isEmpty ? Theme.textTertiary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newCode.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: The list

    @ViewBuilder
    private var friendsList: some View {
        if social.friendCodes.isEmpty {
            EmptyStateView(
                icon: "person.2",
                title: "No friends yet",
                message: "Add a code above to start seeing what your friends are focusing on."
            )
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 10) {
                ForEach(social.friendCodes, id: \.self) { code in
                    friendRow(code: code)
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(code: String) -> some View {
        let status = social.friends.first { $0.presence.code == code }
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: status.map { $0.presence.busy.colorHex } ?? 0x5E646D))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(status?.presence.displayName ?? code)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle(for: status))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let status {
                Text("\(status.presence.momentum)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            Button {
                social.removeFriend(code: code)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func subtitle(for status: FriendStatus?) -> String {
        guard let status else {
            return paid.isReady(.friends) ? "Waiting for their next update…" : "Turn on Chronos+ to see status"
        }
        if status.isStale { return "\(status.presence.busy.label) · last seen a while ago" }
        if let block = status.presence.currentBlockTitle, !block.isEmpty {
            return "\(status.presence.busy.label) · \(block)"
        }
        return status.presence.busy.label
    }

    private var lockedNote: some View {
        Text("Friends presence turns on with Chronos+ (uses your iCloud). Your code and friends list are saved and ready now.")
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

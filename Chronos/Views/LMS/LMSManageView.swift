import SwiftUI

/// Manage connected schools: see each feed's status, sync on demand, unlink,
/// or add another. Also flags device-only subscriptions with a guided fix so
/// the school calendar syncs across all the user's Apple devices via iCloud.
struct LMSManageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @ObservedObject private var lms = LMSStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pendingRemoval: LMSSource?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if lms.sources.isEmpty {
                        EmptyStateView(
                            icon: "graduationcap",
                            title: "No school connected",
                            message: "Connect Canvas or Schoology and assignments become reminders automatically."
                        )
                    } else {
                        ForEach(lms.sources) { source in
                            sourceCard(source)
                        }
                        syncCard
                    }
                    addButton
                }
                .padding(18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .chronosAppearance()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
        .confirmationDialog(
            "Unlink \u{201C}\(pendingRemoval?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unlink School", role: .destructive) {
                if let source = pendingRemoval {
                    lms.remove(source, service: service)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Syncing stops and its class events reappear on your calendar. Assignments already imported stay in Reminders.")
        }
    }

    private var topBar: some View {
        HStack {
            Text("Schools")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: Source card

    private func sourceCard(_ source: LMSSource) -> some View {
        let calendar = service.calendars.first { $0.id == source.calendarID }
        let list = service.taskLists.first { $0.id == source.listID }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accentColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: source.provider.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(lastSyncLabel(source))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button { pendingRemoval = source } label: {
                    Image(systemName: "link.badge.minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 30, height: 30)
                        .background(Theme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Unlink this school")
            }

            HStack(spacing: 14) {
                detailChip("calendar", calendar?.title ?? "Calendar missing", ok: calendar != nil)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                detailChip("checklist", list?.title ?? "List missing", ok: list != nil)
            }

            if calendar?.isLocalSubscription == true {
                iCloudTip
            }
        }
        .panel()
    }

    private func detailChip(_ icon: String, _ title: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ok ? Theme.textSecondary : Theme.warning)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? Theme.textSecondary : Theme.warning)
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.fill, in: Capsule())
    }

    /// iOS webcal subscriptions live on one device only; there's no API to
    /// move them, so guide the user to the iCloud-hosted route.
    private var iCloudTip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Only on this device", systemImage: "exclamationmark.icloud")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text("This subscription doesn't sync through iCloud. To see it on every device: open icloud.com/calendar (or Calendar on a Mac), add a new calendar subscription with the same feed URL choosing iCloud as the location, then re-map this school to that calendar.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func lastSyncLabel(_ source: LMSSource) -> String {
        guard let epoch = source.lastSyncEpoch else { return "Never synced" }
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: Sync + add

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await lms.sync(service: service) }
            } label: {
                HStack(spacing: 8) {
                    if lms.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(lms.isSyncing ? "Syncing…" : "Sync now")
                        .font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.accentColor)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(Theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(lms.isSyncing)

            if let summary = lms.lastSummary {
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Chronos re-imports automatically at launch, when you return to the app, and whenever the calendar changes — at least daily. The feed itself is refreshed by the system on its own schedule (iCloud-hosted subscriptions refresh most reliably).")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addButton: some View {
        Button {
            dismiss()
            model.lmsSetupPresented = true
        } label: {
            Label(lms.sources.isEmpty ? "Connect a school" : "Add another school", systemImage: "plus")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Guided setup for connecting a school LMS (Canvas, Schoology, …). Walks the
/// student through grabbing their calendar feed, subscribing to it in the
/// system Calendar, then maps it to a reminders list and imports assignments.
struct LMSSetupView: View {
    @EnvironmentObject private var service: EventKitService
    @ObservedObject private var lms = LMSStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.accentName) private var accentName = "Blue"

    enum Step { case intro, connect, map, done }
    @State private var step: Step = .intro
    @State private var provider: LMSProvider = .canvas
    @State private var feedText = ""
    @State private var didOpenSubscribe = false
    @State private var selectedCalendarID: String?
    @State private var selectedListID: String?
    @State private var importing = false

    private var editableLists: [CalendarInfo] { service.taskLists.filter(\.isEditable) }
    private var subscribed: [CalendarInfo] { service.subscribedCalendars() }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case .intro: introStep
                    case .connect: connectStep
                    case .map: mapStep
                    case .done: doneStep
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            controls
        }
        .background(Theme.bg)
        .chronosAppearance()
        .tint(Theme.accent(named: accentName))
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    private var topBar: some View {
        HStack {
            Text("Connect your school")
                .font(.system(size: 16, weight: .bold))
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

    // MARK: Intro

    private var introStep: some View {
        VStack(spacing: 18) {
            hero("graduationcap.fill")
            Text("Turn assignments into reminders, automatically")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Text("Chronos can read your Canvas or Schoology calendar feed and turn every assignment into a reminder — with its due date, description, and a link back. Lectures and office hours stay on your calendar as events.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                bullet("checklist", "Assignments become reminders with due dates")
                bullet("calendar", "Classes & office hours stay as calendar events")
                bullet("lock.shield", "Read-only — Chronos never posts to your school")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Connect

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Which platform?")
                .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(LMSProvider.allCases) { p in
                    Button { provider = p } label: {
                        VStack(spacing: 6) {
                            Image(systemName: p.icon).font(.system(size: 19, weight: .semibold))
                            Text(p.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(provider == p ? Theme.accentColor : Theme.textSecondary)
                        .background(provider == p ? Theme.accentColor.opacity(0.14) : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(provider == p ? Theme.accentColor.opacity(0.4) : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(provider.steps.enumerated()), id: \.offset) { idx, text in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                            .frame(width: 18, height: 18)
                            .background(Theme.accentColor.opacity(0.15), in: Circle())
                        Text(text).font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Feed URL").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                TextField("https://…/feed.ics", text: $feedText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }

            Button { openSubscribe() } label: {
                Label("Subscribe in Calendar", systemImage: "calendar.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSubscribe ? Theme.bg : Theme.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(canSubscribe ? Theme.accentColor : Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubscribe)

            Text("This opens the system Calendar and asks you to confirm the subscription. Come back here when you're done.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "icloud")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Text("Want it on every device? Add the subscription at icloud.com/calendar (or in Calendar on a Mac with Location: iCloud) instead — it then syncs everywhere automatically. Subscribing on iPhone keeps it on this device only.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var canSubscribe: Bool { LMSStore.subscribeURL(from: feedText) != nil }

    // MARK: Map

    private var mapStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pick your school calendar")
                        .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button { service.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise").font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accentColor)
                }
                if subscribed.isEmpty {
                    Text("No subscribed calendars found yet. Make sure you tapped Subscribe in the Calendar app, then Refresh.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(subscribed) { cal in
                        selectRow(
                            title: cal.title,
                            subtitle: cal.isLocalSubscription
                                ? "\(cal.sourceTitle) · this device only"
                                : cal.sourceTitle,
                            color: cal.color,
                            selected: selectedCalendarID == cal.id
                        ) {
                            selectedCalendarID = cal.id
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Put assignments in this list")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                if editableLists.isEmpty {
                    Text("No writable reminder lists found.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(editableLists) { list in
                        selectRow(title: list.title, subtitle: list.sourceTitle, color: list.color,
                                  selected: selectedListID == list.id) {
                            selectedListID = list.id
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedListID == nil { selectedListID = editableLists.first?.id }
            if selectedCalendarID == nil { selectedCalendarID = subscribed.first?.id }
        }
    }

    // MARK: Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            hero("checkmark.circle.fill")
            Text("You're connected")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(lms.lastSummary ?? "Your assignments are syncing.")
                .font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text("Chronos will keep your assignments up to date automatically. Manage this anytime in Settings.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            if step == .connect || step == .map {
                Button { back() } label: {
                    Text("Back").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button { advance() } label: {
                HStack(spacing: 7) {
                    if importing { ProgressView().controlSize(.small) }
                    Text(primaryTitle).font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(primaryEnabled ? Theme.accentColor : Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var primaryTitle: String {
        switch step {
        case .intro: return "Get started"
        case .connect: return "I've subscribed"
        case .map: return importing ? "Importing…" : "Import assignments"
        case .done: return "Done"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .intro, .connect: return true
        case .map: return selectedCalendarID != nil && selectedListID != nil && !importing
        case .done: return true
        }
    }

    // MARK: Actions

    private func advance() {
        switch step {
        case .intro: step = .connect
        case .connect:
            service.refresh()
            step = .map
        case .map: runImport()
        case .done: dismiss()
        }
    }

    private func back() {
        switch step {
        case .map: step = .connect
        case .connect: step = .intro
        default: break
        }
    }

    private func runImport() {
        guard let calID = selectedCalendarID, let listID = selectedListID else { return }
        let title = subscribed.first { $0.id == calID }?.title ?? provider.name
        importing = true
        let source = LMSSource(provider: provider, name: title, calendarID: calID, listID: listID, lastSyncEpoch: nil)
        lms.addSource(source)
        Task {
            await lms.sync(service: service)
            importing = false
            step = .done
        }
    }

    private func openSubscribe() {
        guard let url = LMSStore.subscribeURL(from: feedText) else { return }
        didOpenSubscribe = true
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: Bits

    private func hero(_ icon: String) -> some View {
        ZStack {
            Circle().fill(Theme.accentColor.opacity(0.14)).frame(width: 92, height: 92)
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentColor).frame(width: 22)
            Text(text).font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func selectRow(title: String, subtitle: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(selected ? Theme.accentColor : Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.accentColor.opacity(0.4) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

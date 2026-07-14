import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var life: LifeStore

    @State private var restoring = false
    @State private var restoreText = ""
    @State private var restoreFailed = false

    @AppStorage(Prefs.morningReminderEnabled) private var morningReminderEnabled = false
    @AppStorage(Prefs.morningReminderMinutes) private var morningReminderMinutes = 8 * 60
    @AppStorage(Prefs.eveningReminderEnabled) private var eveningReminderEnabled = false
    @AppStorage(Prefs.eveningReminderMinutes) private var eveningReminderMinutes = 21 * 60

    @State private var showingCalibration = false

    @AppStorage(Prefs.accentName) private var accentName = "Indigo"
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""
    @AppStorage(Prefs.dimPastBlocks) private var dimPastBlocks = true
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true
    @AppStorage(Prefs.startAlertsEnabled) private var startAlertsEnabled = true
    @AppStorage(Prefs.blockLiveActivities) private var blockLiveActivities = true

    private var defaultCalendarBinding: Binding<String?> {
        Binding(
            get: { defaultCalendarID.isEmpty ? service.calendars.first(where: \.isEditable)?.id : defaultCalendarID },
            set: { defaultCalendarID = $0 ?? "" }
        )
    }

    private var defaultListBinding: Binding<String?> {
        Binding(
            get: { defaultListID.isEmpty ? service.taskLists.first(where: \.isEditable)?.id : defaultListID },
            set: { defaultListID = $0 ?? "" }
        )
    }

    /// Hidden when presented inside a navigation stack (iOS sheet) that
    /// already supplies a title bar.
    var showsHeader = true

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Tuned for how you plan")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

                Rectangle().fill(Theme.hairline).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    settingsSection("Personalization") {
                        VStack(alignment: .leading, spacing: 8) {
                            if profileStore.profile.isCalibrated {
                                let profile = profileStore.profile
                                Text("Awake \(minuteLabel(profile.wakeMinutes))–\(minuteLabel(profile.bedMinutes)) · \(profile.meals.filter(\.enabled).count) meals · \(profile.routines.count) routines · \(profile.focus.rawValue.lowercased()) focus · \(profile.flexibility.rawValue.lowercased())")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("Not calibrated yet — tell Chronos about your sleep, meals, and routines so Plan My Day can schedule around your life.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Button {
                                showingCalibration = true
                            } label: {
                                Label(
                                    profileStore.profile.isCalibrated ? "Recalibrate" : "Calibrate now",
                                    systemImage: "person.crop.circle.badge.checkmark"
                                )
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    settingsSection("Schedule") {
                        FieldRow(label: "Workday starts") {
                            hourPicker(selection: $workStartMinutes, range: 0...max(min(workEndMinutes / 60 - 1, 23), 0))
                        }
                        FieldRow(label: "Workday ends") {
                            hourPicker(selection: $workEndMinutes, range: min(max(workStartMinutes / 60 + 1, 1), 24)...24)
                        }
                        FieldRow(label: "Snap to") {
                            Picker("", selection: $snapMinutes) {
                                ForEach([5, 10, 15, 30], id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        FieldRow(label: "Default block length") {
                            Picker("", selection: $defaultBlockMinutes) {
                                ForEach([15, 25, 30, 45, 50, 60, 90], id: \.self) { minutes in
                                    Text(Fmt.duration(minutes: minutes)).tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        FieldRow(label: "Plan My Day breathing room") {
                            Picker("", selection: $gapMinutes) {
                                ForEach([0, 5, 10, 15], id: \.self) { minutes in
                                    Text(minutes == 0 ? "None" : "\(minutes) min").tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    settingsSection("Defaults") {
                        CalendarPickerRow(
                            label: "New blocks go to",
                            options: service.calendars,
                            selection: defaultCalendarBinding
                        )
                        CalendarPickerRow(
                            label: "New tasks go to",
                            options: service.taskLists,
                            selection: defaultListBinding
                        )
                    }

                    settingsSection("Notifications") {
                        FieldRow(label: "Enable notifications") {
                            Toggle("", isOn: Binding(
                                get: { notifications.enabled },
                                set: { newValue in
                                    notifications.enabled = newValue
                                    if newValue {
                                        Task {
                                            await notifications.requestAuthorization()
                                            notifications.rescheduleCheckIns(for: service.blocks, startAlerts: startAlertsEnabled)
                                        }
                                    } else {
                                        notifications.cancelAll()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        if notifications.enabled && notifications.authorization == .denied {
                            Text("Notifications are turned off in system settings. Enable them for Chronos in Settings > Notifications.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.warning)
                                .padding(.horizontal, 4)
                        } else {
                            Text("Heads-up before each block starts, and a check-in when a task-linked block ends so you can reschedule what slipped.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4)
                        }

                        if notifications.enabled {
                            FieldRow(label: "Block start alerts") {
                                Toggle("", isOn: $startAlertsEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            #if os(iOS)
                            FieldRow(label: "Current block on Lock Screen") {
                                Toggle("", isOn: $blockLiveActivities)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            #endif
                            FieldRow(label: "Morning planning reminder") {
                                HStack(spacing: 10) {
                                    if morningReminderEnabled {
                                        DatePicker("", selection: minuteBinding($morningReminderMinutes), displayedComponents: [.hourAndMinute])
                                            .labelsHidden()
                                    }
                                    Toggle("", isOn: $morningReminderEnabled).labelsHidden().toggleStyle(.switch)
                                }
                            }
                            FieldRow(label: "Evening reflection reminder") {
                                HStack(spacing: 10) {
                                    if eveningReminderEnabled {
                                        DatePicker("", selection: minuteBinding($eveningReminderMinutes), displayedComponents: [.hourAndMinute])
                                            .labelsHidden()
                                    }
                                    Toggle("", isOn: $eveningReminderEnabled).labelsHidden().toggleStyle(.switch)
                                }
                            }
                        }
                    }

                    settingsSection("Appearance") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Accent")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 10) {
                                ForEach(Theme.accentChoices) { choice in
                                    Button {
                                        accentName = choice.name
                                    } label: {
                                        Circle()
                                            .fill(choice.color)
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        accentName == choice.name ? Theme.textPrimary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                                    .padding(-3)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(choice.name)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        FieldRow(label: "Dim past blocks") {
                            Toggle("", isOn: $dimPastBlocks)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    settingsSection("AI Coach") {
                        VStack(alignment: .leading, spacing: 8) {
                            FieldRow(label: "Show Coach tab") {
                                Toggle("", isOn: $coachEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            Text(coachEnabled
                                 ? "The Coach is a conversational planner. When your device supports Apple Intelligence it runs a private, on-device model; otherwise it uses fast built-in guidance."
                                 : "The Coach tab is hidden. Turn it back on anytime to chat with your planning companion.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 2)
                        }
                    }

                    settingsSection("Sync") {
                        VStack(alignment: .leading, spacing: 6) {
                            Label {
                                Text("Chronos has no database. Blocks are Apple Calendar events; tasks are Apple Reminders. Edits made anywhere — including Siri, the Apple apps, or other devices — appear here automatically, and vice-versa.")
                            } icon: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        Button {
                            service.refresh()
                        } label: {
                            Label("Refresh now", systemImage: "arrow.clockwise")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }

                    settingsSection("Account") {
                        Button {
                            model.statsPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Statistics")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Completion, focus, budgets, achievements")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if LMSStore.shared.isConfigured {
                                model.lmsManagePresented = true
                            } else {
                                model.lmsSetupPresented = true
                            }
                            model.settingsPresented = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(LMSStore.shared.isConfigured ? "Manage schools" : "Connect your school")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Canvas, Schoology — assignments become reminders")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.settingsPresented = false
                            TourController.shared.start()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "map")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Take the tour")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("A guided walkthrough of every screen")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection("Backup") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                ShareLink(item: life.exportJSON()) {
                                    Label("Back up Grow data", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                Button {
                                    restoreText = ""; restoring = true
                                } label: {
                                    Label("Restore", systemImage: "square.and.arrow.down")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Exports your goals, habits, journal, templates & budgets as JSON. Blocks and tasks already live in Apple Calendar & Reminders.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 2)
                        }
                    }

                    settingsSection("About") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chronos")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Version \(Self.appVersion)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Time-blocking built on Apple Calendar & Reminders.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showingCalibration) {
            CalibrationView()
        }
        .alert("Restore from backup", isPresented: $restoring) {
            TextField("Paste backup JSON", text: $restoreText)
            Button("Restore", role: .destructive) {
                if life.importJSON(restoreText) { Haptics.success() } else { restoreFailed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your current goals, habits, journal, templates & budgets.")
        }
        .alert("Couldn't restore", isPresented: $restoreFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That doesn't look like a valid Chronos backup.")
        }
    }

    private func minuteLabel(_ minutes: Int) -> String {
        Fmt.time.string(from: Date().startOfDay.at(minutes: minutes))
    }

    private func minuteBinding(_ source: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Date().startOfDay.at(minutes: source.wrappedValue) },
            set: { source.wrappedValue = $0.minutesSinceMidnight }
        )
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func hourPicker(selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(Array(range), id: \.self) { hour in
                Text(hour == 24
                     ? "Midnight"
                     : Fmt.hourLabel.string(from: Date().startOfDay.at(minutes: hour * 60)))
                    .tag(hour * 60)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

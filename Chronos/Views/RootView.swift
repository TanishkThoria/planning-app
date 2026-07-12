import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var life: LifeStore
    @AppStorage(Prefs.accentName) private var accentName = "Indigo"
    @AppStorage(Prefs.morningReminderEnabled) private var morningReminderEnabled = false
    @AppStorage(Prefs.morningReminderMinutes) private var morningReminderMinutes = 8 * 60
    @AppStorage(Prefs.eveningReminderEnabled) private var eveningReminderEnabled = false
    @AppStorage(Prefs.eveningReminderMinutes) private var eveningReminderMinutes = 21 * 60
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if service.hasFullAccess {
                mainInterface
                    .overlay(alignment: .bottom) {
                        FocusTimerPill()
                            .padding(.bottom, 16)
                    }
            } else {
                PermissionGateView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent(named: accentName))
        .task {
            // Route completed focus stretches into the persistent log.
            timer.onSessionComplete = { [weak focusLog] session in
                focusLog?.record(session)
            }
            await service.requestAccess()
            if service.hasFullAccess && !profileStore.profile.isCalibrated {
                model.calibrationPresented = true
            }
            await notifications.refreshAuthorization()
            rescheduleRituals()
            rescheduleHabitReminders()
        }
        .onChange(of: morningReminderEnabled) { _, _ in rescheduleRituals() }
        .onChange(of: morningReminderMinutes) { _, _ in rescheduleRituals() }
        .onChange(of: eveningReminderEnabled) { _, _ in rescheduleRituals() }
        .onChange(of: eveningReminderMinutes) { _, _ in rescheduleRituals() }
        .onChange(of: model.selectedDate) { _, newDate in
            service.ensureWindow(around: newDate)
        }
        .onChange(of: service.blocks) { _, blocks in
            notifications.rescheduleCheckIns(for: blocks)
        }
        .onChange(of: life.habits) { _, _ in rescheduleHabitReminders() }
        .onChange(of: notifications.enabled) { _, _ in
            rescheduleRituals()
            rescheduleHabitReminders()
        }
        .sheet(item: $model.blockEditor) { context in
            BlockEditorView(context: context)
        }
        .sheet(item: $model.taskEditor) { context in
            TaskEditorView(context: context)
        }
        .sheet(isPresented: $model.quickAddPresented) {
            QuickAddView()
        }
        .sheet(isPresented: $model.planDayPresented) {
            PlanMyDayView()
        }
        .sheet(isPresented: $model.planWeekPresented) {
            PlanWeekView()
        }
        .sheet(isPresented: $model.calibrationPresented) {
            CalibrationView()
        }
        .sheet(isPresented: $model.morningPlanningPresented) {
            MorningPlanningView()
        }
        .sheet(isPresented: $model.reviewPresented) {
            DayReviewView(day: model.selectedDate.isToday ? model.selectedDate : Date().startOfDay)
        }
        .sheet(isPresented: $model.focusTimerPresented, onDismiss: { model.focusTimerContext = nil }) {
            FocusTimerView(
                presetTaskID: model.focusTimerContext?.taskID,
                presetTitle: model.focusTimerContext?.title
            )
        }
        .sheet(item: $model.goalEditor) { context in
            GoalEditorView(context: context)
        }
        .sheet(item: $model.habitEditor) { context in
            HabitEditorView(context: context)
        }
        .sheet(isPresented: $model.journalPresented) {
            JournalView()
        }
        .sheet(isPresented: $model.templatesPresented) {
            TemplatesView()
        }
        .sheet(isPresented: $model.budgetsPresented) {
            BudgetsView()
        }
        .sheet(isPresented: $model.calendarFilterPresented) {
            CalendarFilterView()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { service.lastError != nil },
                set: { if !$0 { service.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(service.lastError?.message ?? "")
        }
    }

    @ViewBuilder
    private var mainInterface: some View {
        #if os(macOS)
        splitLayout
        #else
        if horizontalSizeClass == .regular {
            splitLayout
        } else {
            compactLayout
        }
        #endif
    }

    private var splitLayout: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .background(Theme.bg)
    }

    #if os(iOS)
    private var compactLayout: some View {
        TabView(selection: $model.screen) {
            ForEach(AppModel.Screen.compactTabs) { screen in
                screenView(screen)
                    .tabItem {
                        Label(screen.title, systemImage: model.screen == screen ? screen.iconFilled : screen.icon)
                    }
                    .tag(screen)
            }
        }
        .sheet(isPresented: $model.settingsPresented) {
            NavigationStack {
                SettingsView(showsHeader: false)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.settingsPresented = false }
                        }
                    }
            }
        }
    }
    #endif

    private var detail: some View {
        screenView(model.screen)
            #if os(macOS)
            .navigationTitle("")
            #endif
    }

    @ViewBuilder
    private func screenView(_ screen: AppModel.Screen) -> some View {
        switch screen {
        case .today: TodayView()
        case .calendar: PlannerScreen()
        case .tasks: TasksView()
        case .grow: GrowView()
        case .insights: InsightsView()
        case .settings: SettingsView()
        }
    }

    // MARK: Notification scheduling helpers

    private func rescheduleRituals() {
        notifications.scheduleRituals(
            morningMinutes: morningReminderEnabled ? morningReminderMinutes : nil,
            eveningMinutes: eveningReminderEnabled ? eveningReminderMinutes : nil
        )
    }

    private func rescheduleHabitReminders() {
        let reminders = life.activeHabits.compactMap { habit -> (id: String, title: String, minutes: Int)? in
            guard let minutes = habit.reminderMinutes else { return nil }
            return (id: habit.id.uuidString, title: habit.title, minutes: minutes)
        }
        notifications.scheduleHabitReminders(reminders)
    }
}

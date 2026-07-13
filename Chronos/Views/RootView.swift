import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var life: LifeStore
    @ObservedObject private var intentLauncher = IntentLauncher.shared
    @ObservedObject private var tour = TourController.shared
    @AppStorage(Prefs.accentName) private var accentName = "Indigo"
    @AppStorage("chronos.onboardingComplete") private var onboardingComplete = false
    @AppStorage(Prefs.morningReminderEnabled) private var morningReminderEnabled = false
    @AppStorage(Prefs.morningReminderMinutes) private var morningReminderMinutes = 8 * 60
    @AppStorage(Prefs.eveningReminderEnabled) private var eveningReminderEnabled = false
    @AppStorage(Prefs.eveningReminderMinutes) private var eveningReminderMinutes = 21 * 60
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // Split into staged helpers so the type-checker isn't handed one giant
    // modifier chain (it times out past a certain size). Each helper has an
    // explicit `some View` body that's checked independently.
    var body: some View {
        onboardingGate(errorAlert(sheets(lifecycle(rootContent))))
            .overlay {
                if tour.isActive {
                    TourOverlay().transition(.opacity)
                }
            }
            .onChange(of: tour.isActive) { _, active in
                // After the tour wraps up, nudge new users into calibration.
                if !active, service.hasFullAccess, !profileStore.profile.isCalibrated {
                    model.calibrationPresented = true
                }
            }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !onboardingComplete }, set: { if !$0 { onboardingComplete = true } })
    }

    private func finishOnboarding() {
        onboardingComplete = true
        // Hand new users straight into the interactive tour of the live app.
        if service.hasFullAccess {
            withAnimation(.snappy) { tour.start() }
        }
    }

    private func onboardingGate<Content: View>(_ content: Content) -> some View {
        content
        #if os(iOS)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(onFinish: finishOnboarding)
                .interactiveDismissDisabled()
        }
        #else
        .sheet(isPresented: onboardingBinding) {
            OnboardingView(onFinish: finishOnboarding)
                .interactiveDismissDisabled()
        }
        #endif
    }

    private var rootContent: some View {
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
    }

    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
        .onOpenURL { url in
            model.handleDeepLink(url)
        }
        .task {
            // Route completed focus stretches into the persistent log.
            timer.onSessionComplete = { [weak focusLog] session in
                focusLog?.record(session)
            }
            // Onboarding owns the first-run permission flow; only auto-request
            // here once it's been completed, so we never double-prompt.
            if onboardingComplete {
                await service.requestAccess()
                if service.hasFullAccess && !profileStore.profile.isCalibrated {
                    model.calibrationPresented = true
                }
            }
            await notifications.refreshAuthorization()
            rescheduleRituals()
            rescheduleHabitReminders()
            LiveActivityController.shared.accentHex = Theme.accent(named: accentName).hexRGB
            refreshWidgetSnapshot()
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
            refreshWidgetSnapshot()
        }
        .onChange(of: service.tasks) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: life.habits) { _, _ in
            rescheduleHabitReminders()
            refreshWidgetSnapshot()
        }
        .onChange(of: life.habitCompletions) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: accentName) { _, name in
            LiveActivityController.shared.accentHex = Theme.accent(named: name).hexRGB
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshWidgetSnapshot() }
        }
        .onChange(of: notifications.enabled) { _, _ in
            rescheduleRituals()
            rescheduleHabitReminders()
        }
        .onChange(of: intentLauncher.pendingAction) { _, action in
            // A Siri/Shortcuts intent asked to open the app to plan today.
            if action == .planToday {
                model.screen = .today
                model.morningPlanningPresented = true
                intentLauncher.pendingAction = nil
            }
        }
        .onChange(of: notifications.pendingRoute) { _, route in
            guard let route else { return }
            handleNotificationRoute(route)
            notifications.pendingRoute = nil
        }
    }

    private func handleNotificationRoute(_ route: NotificationService.Route) {
        switch route {
        case .checkIn:
            model.screen = .today
            model.reviewPresented = true
        case .planMorning:
            model.screen = .today
            model.morningPlanningPresented = true
        case .reflectEvening:
            model.eveningRitualPresented = true
        case .grow:
            model.screen = .grow
        }
    }

    private func sheets<Content: View>(_ content: Content) -> some View {
        content
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
        .sheet(isPresented: $model.reflowPresented) {
            ReflowView()
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
        .sheet(isPresented: $model.morningRitualPresented) {
            MorningRitualView()
        }
        .sheet(isPresented: $model.eveningRitualPresented) {
            EveningRitualView()
        }
        .sheet(isPresented: $model.weeklyReviewPresented) {
            WeeklyReviewView()
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
        .sheet(isPresented: $model.searchPresented) {
            SearchView()
        }
        .sheet(isPresented: $model.overdueSweepPresented) {
            OverdueSweepView()
        }
        .sheet(isPresented: $model.statsPresented) {
            StatisticsView(onClose: { model.statsPresented = false })
                .preferredColorScheme(.dark)
        }
    }

    private func errorAlert<Content: View>(_ content: Content) -> some View {
        content
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
        case .coach: CoachView()
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

    private func refreshWidgetSnapshot() {
        SnapshotWriter.refresh(service: service, life: life, accentName: accentName)
    }

    private func rescheduleHabitReminders() {
        let reminders = life.activeHabits.compactMap { habit -> (id: String, title: String, minutes: Int)? in
            guard let minutes = habit.reminderMinutes else { return nil }
            return (id: habit.id.uuidString, title: habit.title, minutes: minutes)
        }
        notifications.scheduleHabitReminders(reminders)
    }
}

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
    @ObservedObject private var lms = LMSStore.shared
    @AppStorage(Prefs.accentName) private var accentName = "Indigo"
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true
    @AppStorage("chronos.onboardingComplete") private var onboardingComplete = false
    @AppStorage(Prefs.morningReminderEnabled) private var morningReminderEnabled = false
    @AppStorage(Prefs.morningReminderMinutes) private var morningReminderMinutes = 8 * 60
    @AppStorage(Prefs.eveningReminderEnabled) private var eveningReminderEnabled = false
    @AppStorage(Prefs.eveningReminderMinutes) private var eveningReminderMinutes = 21 * 60
    @AppStorage(Prefs.startAlertsEnabled) private var startAlertsEnabled = true
    @AppStorage(Prefs.blockLiveActivities) private var blockLiveActivities = true
    @Environment(\.scenePhase) private var scenePhase
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
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
            .onChange(of: coachEnabled) { _, enabled in
                // If the Coach tab is hidden while it's showing, fall back to Today.
                if !enabled, model.screen == .coach {
                    model.screen = .today
                }
            }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !onboardingComplete }, set: { if !$0 { onboardingComplete = true } })
    }

    private func finishOnboarding(connectLMS: Bool) {
        onboardingComplete = true
        if connectLMS {
            // Students opted in — take them straight to the school connect flow.
            model.lmsSetupPresented = true
        } else if service.hasFullAccess {
            // Otherwise hand them into the interactive tour of the live app.
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
        .fullScreenCover(isPresented: $model.nowModePresented) { NowView() }
        #else
        .sheet(isPresented: onboardingBinding) {
            OnboardingView(onFinish: finishOnboarding)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.nowModePresented) { NowView() }
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
        .chronosAppearance()
        .tint(Theme.accent(named: accentName))
    }

    // Staged (lifecycle → dataObservers → settingObservers) so no single
    // modifier chain overwhelms the type-checker.
    private func lifecycle<Content: View>(_ content: Content) -> some View {
        settingObservers(dataObservers(content))
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
            // Keep hidden assignment events hidden immediately, then pull any
            // new LMS assignments in the background.
            lms.applyHidden(to: service)
            if lms.isConfigured, service.hasFullAccess {
                await lms.autoSyncIfStale(service: service)
            }
            // Chronos+ (paid): detect availability, then sync/connect if ready.
            // All of this no-ops cleanly on the free account.
            PaidFeatures.shared.refresh()
            await CloudSyncService.shared.syncNow()
            SocialService.shared.authenticateGameCenter()
            syncSocialPresence()
            submitLeaderboards()
        }
    }

    /// Reactions to live data changing (calendar, tasks, habits, the clock).
    private func dataObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: model.selectedDate) { _, newDate in
            service.ensureWindow(around: newDate)
        }
        .onChange(of: service.blocks) { _, blocks in
            notifications.rescheduleCheckIns(for: blocks, startAlerts: startAlertsEnabled)
            refreshWidgetSnapshot()
            syncBlockActivity()
            syncSocialPresence()
            // Feed updates arrive as calendar changes — pull new assignments
            // (throttled so our own imports don't loop it).
            Task { await lms.autoSyncIfStale(service: service, minInterval: 30 * 60) }
        }
        .onChange(of: service.tasks) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: life.habits) { _, _ in
            rescheduleHabitReminders()
            refreshWidgetSnapshot()
        }
        .onChange(of: life.habitCompletions) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: timer.isActive) { _, _ in syncBlockActivity() }
        .onReceive(minuteTick) { _ in
            syncBlockActivity()
            syncSocialPresence()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshWidgetSnapshot()
                syncBlockActivity()
                PaidFeatures.shared.refresh()
                Task {
                    await CloudSyncService.shared.syncNow()
                    await SocialService.shared.refreshFriends()
                }
                submitLeaderboards()
                // Guarantees at-least-daily assignment imports for anyone who
                // opens the app daily; 6h staleness keeps it fresher than that.
                Task { await lms.autoSyncIfStale(service: service) }
            } else if phase == .background {
                Task { await CloudSyncService.shared.pushIfReady() }
            }
        }
    }

    // MARK: Chronos+ social helpers (all no-op unless the feature is ready)

    /// Publishes the user's current block + busy level so friends can see it.
    private func syncSocialPresence() {
        let now = Date()
        let current = service.blocks(on: now.startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
            .first { !$0.isAllDay && $0.start <= now && now < $0.end }
        let busy: BusyLevel
        if timer.isActive {
            busy = .headsDown
        } else if let current {
            let deep = current.notes?.localizedCaseInsensitiveContains("energy:deep") ?? false
            busy = deep ? .headsDown : .busy
        } else {
            busy = .free
        }
        SocialService.shared.publishPresence(
            currentBlockTitle: current?.title,
            busy: busy,
            momentum: MomentumStore.shared.score(on: now)
        )
    }

    private func submitLeaderboards() {
        SocialService.shared.submitWeeklyFocus(minutes: focusLog.totalMinutes(inLast: 7))
        SocialService.shared.submitMomentum(MomentumStore.shared.totalPoints)
    }

    /// Reactions to preferences and inbound routing (intents, notifications).
    private func settingObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: morningReminderEnabled) { _, _ in rescheduleRituals() }
        .onChange(of: morningReminderMinutes) { _, _ in rescheduleRituals() }
        .onChange(of: eveningReminderEnabled) { _, _ in rescheduleRituals() }
        .onChange(of: eveningReminderMinutes) { _, _ in rescheduleRituals() }
        .onChange(of: startAlertsEnabled) { _, on in
            notifications.rescheduleCheckIns(for: service.blocks, startAlerts: on)
        }
        .onChange(of: blockLiveActivities) { _, _ in syncBlockActivity() }
        .onChange(of: accentName) { _, name in
            LiveActivityController.shared.accentHex = Theme.accent(named: name).hexRGB
        }
        .onChange(of: notifications.enabled) { _, _ in
            rescheduleRituals()
            rescheduleHabitReminders()
        }
        .onChange(of: intentLauncher.pendingAction) { _, action in
            // A Siri/Shortcuts intent asked to open the app somewhere specific.
            switch action {
            case .planToday:
                model.screen = .today
                model.morningPlanningPresented = true
            case .eatFrog:
                model.screen = .today
                if let frogID = model.frogTaskID,
                   let frog = service.task(withID: frogID), !frog.isCompleted {
                    timer.focusMinutes = 5
                    timer.start(taskID: frog.id, title: frog.title, mode: .pomodoro)
                    model.focusTimerPresented = true
                }
            case nil:
                break
            }
            if action != nil { intentLauncher.pendingAction = nil }
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
        case .openToday:
            model.screen = .today
        }
    }

    /// Keep the Lock Screen / Dynamic Island showing the block you're in.
    /// The focus timer's Live Activity always wins over the block one.
    private func syncBlockActivity() {
        let now = Date()
        let current = blockLiveActivities
            ? service.blocks(on: now.startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
                .first { !$0.isAllDay && $0.start <= now && now < $0.end }
            : nil
        LiveActivityController.shared.syncBlock(current, focusActive: timer.isActive)
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
                .chronosAppearance()
        }
        .sheet(isPresented: $model.commandBarPresented, onDismiss: runPendingCommand) {
            CommandBarView()
        }
        .sheet(isPresented: $model.lmsSetupPresented) {
            LMSSetupView()
        }
        .sheet(isPresented: $model.lmsManagePresented) {
            LMSManageView()
        }
        .sheet(isPresented: $model.trendsPresented) {
            TrendsView()
        }
        .sheet(isPresented: $model.timeReportPresented) {
            TimeReportView()
        }
        .sheet(isPresented: $model.wrappedPresented) {
            WrappedView()
        }
        .sheet(isPresented: $model.deadlinePlanPresented) {
            DeadlinePlanView()
        }
        .sheet(isPresented: $model.availabilityPresented) {
            AvailabilityView()
        }
        .sheet(isPresented: $model.chronosPlusPresented) {
            ChronosPlusView()
        }
        .sheet(isPresented: $model.leaderboardPresented) {
            LeaderboardView()
        }
        .sheet(isPresented: $model.friendsPresented) {
            FriendsView()
        }
        .sheet(isPresented: $model.coachPresented) {
            CoachView()
                .chronosAppearance()
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

    /// The primary tabs, minus the Coach when the user has turned it off.
    private var visibleTabs: [AppModel.Screen] {
        AppModel.Screen.compactTabs.filter { coachEnabled || $0 != .coach }
    }

    #if os(iOS)
    private var compactLayout: some View {
        TabView(selection: $model.screen) {
            ForEach(visibleTabs) { screen in
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
        SnapshotWriter.refresh(service: service, life: life, focusLog: focusLog, accentName: accentName)
    }

    /// Runs the command bar's chosen action after its sheet has dismissed, so
    /// it can safely open another sheet.
    private func runPendingCommand() {
        let action = model.pendingCommandBarAction
        model.pendingCommandBarAction = nil
        action?()
    }

    private func rescheduleHabitReminders() {
        let reminders = life.activeHabits.compactMap { habit -> (id: String, title: String, minutes: Int)? in
            guard let minutes = habit.reminderMinutes else { return nil }
            return (id: habit.id.uuidString, title: habit.title, minutes: minutes)
        }
        notifications.scheduleHabitReminders(reminders)
    }
}

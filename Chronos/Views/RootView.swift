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
    @ObservedObject private var achievements = AchievementStore.shared
    @AppStorage(Prefs.accentName) private var accentName = "Blue"
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true
    @AppStorage("chronos.onboardingComplete") private var onboardingComplete = false
    /// The interactive tour has run (or been skipped) at least once.
    @AppStorage("chronos.tourSeen") private var tourSeen = false
    /// Calibration has been offered once — completed or skipped — so we stop
    /// re-presenting it on every launch.
    @AppStorage("chronos.calibrationOffered") private var calibrationOffered = false
    /// The last day the app was opened — powers the no-guilt "welcome back" after
    /// time away (Day Zero).
    @AppStorage("chronos.lastOpenDay") private var lastOpenDay = ""
    @AppStorage(Prefs.morningReminderEnabled) private var morningReminderEnabled = false
    @AppStorage(Prefs.morningReminderMinutes) private var morningReminderMinutes = 8 * 60
    @AppStorage(Prefs.eveningReminderEnabled) private var eveningReminderEnabled = false
    @AppStorage(Prefs.eveningReminderMinutes) private var eveningReminderMinutes = 21 * 60
    @AppStorage(Prefs.startAlertsEnabled) private var startAlertsEnabled = true
    @AppStorage(Prefs.blockLiveActivities) private var blockLiveActivities = true
    @Environment(\.scenePhase) private var scenePhase
    /// A student opted into school setup; continue into the tour once it closes.
    @State private var chainGuidanceAfterLMS = false
    /// The user finished onboarding this session without granting access yet;
    /// route them into the tour the moment they grant at the permission gate.
    /// Session-scoped so existing users never get a surprise tour on relaunch.
    @State private var awaitingFirstRunAccess = false
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
                } else if onboardingComplete, let celebration = achievements.current {
                    CelebrationOverlay(celebration: celebration) {
                        achievements.dismissCurrent()
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .onChange(of: tour.isActive) { _, active in
                // Tour finished (or was skipped) — remember it, then hand new
                // users into calibration once any demo sheet has closed.
                if !active {
                    tourSeen = true
                    if service.hasFullAccess, !profileStore.profile.isCalibrated, !calibrationOffered {
                        model.commandBarPresented = false
                        DispatchQueue.main.async { model.calibrationPresented = true }
                    }
                }
            }
            .onChange(of: service.hasFullAccess) { _, granted in
                // Granting from the permission gate (rather than during
                // onboarding) — route into first-run guidance, but only for a
                // user who just onboarded this session, never existing users.
                if granted, awaitingFirstRunAccess {
                    awaitingFirstRunAccess = false
                    startFirstRunGuidanceIfNeeded()
                }
            }
            .onChange(of: model.lmsSetupPresented) { _, presented in
                // School setup closed on first run → continue into the tour.
                if !presented, chainGuidanceAfterLMS {
                    chainGuidanceAfterLMS = false
                    startFirstRunGuidanceIfNeeded()
                }
            }
            .onChange(of: coachEnabled) { _, enabled in
                // If the Coach tab is hidden while it's showing, fall back to Today.
                if !enabled, model.screen == .coach {
                    model.screen = .today
                }
            }
    }

    /// The single entry point into first-run guidance, safe to call from every
    /// path (onboarding finished, school setup closed, access granted at the
    /// gate). Runs the tour first (once), then calibration — and no-ops when
    /// neither is needed, so it never loops or double-presents.
    private func startFirstRunGuidanceIfNeeded() {
        guard onboardingComplete, service.hasFullAccess, !tour.isActive else { return }
        if !tourSeen {
            withAnimation(.snappy) { tour.start() }
        } else if !calibrationOffered, !profileStore.profile.isCalibrated {
            DispatchQueue.main.async { model.calibrationPresented = true }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !onboardingComplete }, set: { if !$0 { onboardingComplete = true } })
    }

    private func finishOnboarding(connectLMS: Bool) {
        onboardingComplete = true
        if connectLMS {
            // Students opted in — school setup first, then the tour rejoins the
            // same guidance when it closes. Defer the sheet so it doesn't race
            // the onboarding cover's dismissal (which drops it silently).
            chainGuidanceAfterLMS = true
            DispatchQueue.main.async { model.lmsSetupPresented = true }
        } else if service.hasFullAccess {
            startFirstRunGuidanceIfNeeded()
        } else {
            // They skipped granting during onboarding — pick up the tour when
            // they grant at the permission gate.
            awaitingFirstRunAccess = true
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
        // Re-key on the accent so every `Theme.accentColor` in the tree is
        // re-read the instant the preference changes — a full, live recolor.
        // Accent changes originate in the Settings sheet, so this rebuild is
        // off-screen and imperceptible.
        .id(accentName)
    }

    // Staged (lifecycle → dataObservers → settingObservers) so no single
    // modifier chain overwhelms the type-checker.
    private func lifecycle<Content: View>(_ content: Content) -> some View {
        settingObservers(dataObservers(content))
        .onOpenURL { url in
            model.handleDeepLink(url)
        }
        .task {
            // Route completed focus stretches into the persistent log. If the
            // session was tagged with a habit, count it done for today too.
            timer.onSessionComplete = { [weak focusLog, weak life] session in
                focusLog?.record(session)
                if let habitID = session.habitID,
                   let habit = life?.habits.first(where: { $0.id == habitID }),
                   life?.isDone(habit, on: Date()) == false {
                    life?.toggle(habit, on: Date())
                }
                // A project-tagged session banks its minutes on the project.
                if let projectID = session.projectID, session.actualMinutes >= 1 {
                    life?.logTime(to: projectID, minutes: session.actualMinutes,
                                  note: session.taskTitle == "Focus" ? "Focus session" : session.taskTitle)
                }
            }
            // Onboarding owns the first-run permission flow; only auto-request
            // here once it's been completed, so we never double-prompt.
            if onboardingComplete {
                await service.requestAccess()
                if service.hasFullAccess && !profileStore.profile.isCalibrated && !calibrationOffered {
                    model.calibrationPresented = true
                }
            }
            await notifications.refreshAuthorization()
            rescheduleRituals()
            rescheduleHabitReminders()
            checkGamification()
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
            CloudKeyValueBackup.shared.start()
            await CloudSyncService.shared.syncNow()
            SocialService.shared.authenticateGameCenter()
            syncSocialPresence()
            submitLeaderboards()
            checkDayZero()
        }
    }

    /// Show the no-guilt "welcome back" screen for an established user returning
    /// after a few days away — never during onboarding, calibration, or the tour.
    private func checkDayZero() {
        let todayKey = Fmt.dayKey(Date())
        defer { lastOpenDay = todayKey }
        guard onboardingComplete, service.hasFullAccess,
              profileStore.profile.isCalibrated, !tour.isActive,
              !lastOpenDay.isEmpty, lastOpenDay != todayKey,
              let last = Fmt.day(fromKey: lastOpenDay) else { return }
        let gap = Calendar.current.dateComponents([.day], from: last, to: Date().startOfDay).day ?? 0
        if gap >= 3 {
            DispatchQueue.main.async { model.welcomeBackPresented = true }
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
        .onChange(of: service.tasks) { _, _ in refreshWidgetSnapshot(); checkGamification() }
        .onChange(of: life.habits) { _, _ in
            rescheduleHabitReminders()
            refreshWidgetSnapshot()
        }
        .onChange(of: life.habitCompletions) { _, _ in refreshWidgetSnapshot(); checkGamification() }
        .onChange(of: timer.isActive) { _, _ in syncBlockActivity() }
        .onReceive(minuteTick) { _ in
            syncBlockActivity()
            syncSocialPresence()
        }
        .onChange(of: focusLog.sessions.count) { _, _ in checkGamification() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshWidgetSnapshot()
                syncBlockActivity()
                checkGamification()
                PaidFeatures.shared.refresh()
                CloudKeyValueBackup.shared.sync()
                Task {
                    await CloudSyncService.shared.syncNow()
                    await SocialService.shared.refreshFriends()
                }
                submitLeaderboards()
                // Guarantees at-least-daily assignment imports for anyone who
                // opens the app daily; 6h staleness keeps it fresher than that.
                Task { await lms.autoSyncIfStale(service: service) }
            } else if phase == .background {
                CloudKeyValueBackup.shared.backUp()
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
        let doneToday = service.tasks.filter {
            $0.isCompleted && ($0.completionDate?.isToday ?? false)
        }.count
        let stats = SocialStats(
            momentumToday: MomentumStore.shared.score(on: now),
            streakDays: MomentumStore.shared.streak(),
            level: MomentumStore.shared.level,
            focusToday: focusLog.totalMinutes(inLast: 1),
            tasksToday: doneToday,
            weeklyFocus: focusLog.totalMinutes(inLast: 7)
        )
        SocialService.shared.publishPresence(
            blockTitle: current?.title,
            busy: busy,
            stats: stats
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
                .onAppear { PlanningMeter.shared.begin("planDay") }
                .onDisappear { PlanningMeter.shared.end("planDay") }
        }
        .sheet(isPresented: $model.planWeekPresented) {
            PlanWeekView()
                .onAppear { PlanningMeter.shared.begin("planWeek") }
                .onDisappear { PlanningMeter.shared.end("planWeek") }
        }
        .sheet(isPresented: $model.calibrationPresented) {
            CalibrationView()
                .onAppear { PlanningMeter.shared.begin("calibration") }
                .onDisappear { PlanningMeter.shared.end("calibration") }
        }
        .sheet(isPresented: $model.morningPlanningPresented) {
            MorningPlanningView()
                .onAppear { PlanningMeter.shared.begin("morningPlan") }
                .onDisappear { PlanningMeter.shared.end("morningPlan") }
        }
        .sheet(isPresented: $model.reviewPresented) {
            DayReviewView(day: model.selectedDate.isToday ? model.selectedDate : Date().startOfDay)
        }
        .sheet(isPresented: $model.reflowPresented) {
            ReflowView()
                .onAppear { PlanningMeter.shared.begin("reflow") }
                .onDisappear { PlanningMeter.shared.end("reflow") }
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
        .sheet(isPresented: $model.friendChallengesPresented) {
            FriendChallengesView()
        }
        .sheet(isPresented: $model.coachPresented) {
            CoachView()
                .chronosAppearance()
        }
        .sheet(isPresented: $model.momentumDetailPresented, onDismiss: runPendingCommand) {
            MomentumDetailView()
        }
        .sheet(isPresented: $model.achievementsPresented) {
            AchievementsView()
        }
        .sheet(isPresented: $model.challengesPresented) {
            ChallengesView()
        }
        .sheet(isPresented: $model.routinesPresented) {
            RoutinesView()
        }
        .sheet(item: $model.routineRunner) { routine in
            RoutineRunnerView(routine: routine)
        }
        .sheet(isPresented: $model.projectsPresented) {
            ProjectsView()
        }
        .sheet(isPresented: $model.personalGrowthPresented) {
            PersonalGrowthView()
        }
        .sheet(isPresented: $model.niceToHavesPresented) {
            NiceToHavesView()
        }
        .sheet(isPresented: $model.futureSelfPresented) {
            FutureSelfView()
        }
        .sheet(item: $model.pillarEditor) { context in
            IdentityPillarEditorView(context: context)
        }
        .sheet(isPresented: $model.dayIntentPresented) {
            MinimumViableDayView()
        }
        .sheet(isPresented: $model.manualPresented) {
            MyManualView()
        }
        .sheet(isPresented: $model.aspirationsPresented) {
            AspirationVaultView()
        }
        .sheet(item: $model.aspirationEditor) { context in
            AspirationEditorView(context: context)
        }
        .sheet(isPresented: $model.welcomeBackPresented) {
            WelcomeBackView()
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

    /// Records today's momentum and checks for freshly-earned achievements /
    /// level-ups, firing a celebration when something new is unlocked. Cheap and
    /// idempotent — safe to call on launch, on foreground, and after you tick
    /// something off.
    private func checkGamification() {
        guard onboardingComplete else { return }
        let momentum = MomentumStore.shared
        let mInput = MomentumEngine.dailyInput(
            service: service, life: life, focusLog: focusLog,
            hiddenCalendars: model.hiddenCalendarIDs, frogTaskID: model.frogTaskID
        )
        momentum.record(MomentumEngine.score(mInput))

        let today = Date().startOfDay
        let weekDays = (0..<7).map { today.startOfWeek.adding(days: $0) }
        let stats = StatsEngine.compute(
            days: weekDays,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
        )
        let bestHabitStreak = life.activeHabits.map { life.streak($0) }.max() ?? 0
        let bestRoutineStreak = RoutineStore.shared.trackedRoutines.map { RoutineStore.shared.streak($0) }.max() ?? 0
        let inputs = AchievementEngine.Inputs(
            completionStreak: stats.streakDays,
            totalFocusMinutes: focusLog.sessions.reduce(0) { $0 + $1.actualMinutes },
            weekDeepMinutes: stats.deepMinutes,
            onTimeRate: stats.onTimeRate,
            datedCompleted: stats.datedCompleted,
            bestHabitStreak: bestHabitStreak,
            journalStreak: life.journalStreak,
            templatesSaved: life.templates.count,
            weekBlockCount: stats.blockCount,
            momentumLevel: momentum.level,
            momentumStreak: momentum.streak(),
            perfectDays: momentum.perfectDays,
            solidDays: momentum.solidDays,
            bestRoutineStreak: bestRoutineStreak
        )
        achievements.register(AchievementEngine.compute(inputs))
        achievements.registerLevel(momentum.level, title: momentum.levelTitle)
        if momentum.score(on: today) >= 100 {
            achievements.registerMilestone(
                id: "perfect-\(Fmt.dayKey(today))",
                title: "Perfect Day", subtitle: "You maxed out today's momentum. Incredible.",
                icon: "star.circle.fill", colorHex: 0xF2C14E
            )
        }

        // Daily / weekly challenges — award bonus XP + celebrate on completion.
        let metrics = ChallengeMetrics.live(service: service, life: life, focusLog: focusLog,
                                            hiddenCalendars: model.hiddenCalendarIDs, day: today)
        ChallengeStore.shared.check(metrics, on: today)
    }

    private func rescheduleHabitReminders() {
        let reminders = life.activeHabits.compactMap { habit -> (id: String, title: String, minutes: Int, anchored: Bool)? in
            guard let minutes = habit.reminderMinutes else { return nil }
            return (id: habit.id.uuidString, title: habit.title, minutes: minutes, anchored: habit.anchored)
        }
        notifications.scheduleHabitReminders(reminders)

        let routineReminders = RoutineStore.shared.trackedRoutines.compactMap { r -> (id: String, name: String, minutes: Int)? in
            guard let minutes = r.reminderMinutes else { return nil }
            return (id: r.id.uuidString, name: r.name, minutes: minutes)
        }
        notifications.scheduleRoutineReminders(routineReminders)
    }
}

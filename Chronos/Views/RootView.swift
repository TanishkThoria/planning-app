import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @AppStorage(Prefs.accentName) private var accentName = "Indigo"
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if service.hasFullAccess {
                mainInterface
            } else {
                PermissionGateView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent(named: accentName))
        .task {
            await service.requestAccess()
            if service.hasFullAccess && !profileStore.profile.isCalibrated {
                model.calibrationPresented = true
            }
        }
        .onChange(of: model.selectedDate) { _, newDate in
            service.ensureWindow(around: newDate)
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
        .sheet(isPresented: $model.calibrationPresented) {
            CalibrationView()
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
                    .tabItem { Label(screen.title, systemImage: screen.icon) }
                    .tag(screen)
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
        case .day: DayPlannerView()
        case .week: WeekPlannerView()
        case .agenda: AgendaView()
        case .tasks: TasksView()
        case .matrix: MatrixView()
        case .insights: InsightsView()
        case .settings: SettingsView()
        case .more: MoreView()
        }
    }
}

/// iPhone overflow tab: the screens that don't fit in the tab bar.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WeekPlannerView()
                } label: {
                    Label("Week", systemImage: "calendar")
                }
                NavigationLink {
                    InsightsView()
                } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("More")
        }
    }
}

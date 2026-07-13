import SwiftUI

@main
struct ChronosApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var service = EventKitService()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var focusLog = FocusLog()
    @StateObject private var timer = FocusTimerController()
    @StateObject private var notifications = NotificationService()
    @StateObject private var life = LifeStore()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(service)
                .environmentObject(profileStore)
                .environmentObject(focusLog)
                .environmentObject(timer)
                .environmentObject(notifications)
                .environmentObject(life)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            ChronosCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(service)
                .environmentObject(profileStore)
                .environmentObject(focusLog)
                .environmentObject(timer)
                .environmentObject(notifications)
                .environmentObject(life)
                .frame(width: 480, height: 640)
                .preferredColorScheme(.dark)
        }
        #else
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(service)
                .environmentObject(profileStore)
                .environmentObject(focusLog)
                .environmentObject(timer)
                .environmentObject(notifications)
                .environmentObject(life)
        }
        #endif
    }
}

#if os(macOS)
/// Full keyboard control for power users — every core action has a chord.
struct ChronosCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Quick Add…") { model.quickAddPresented = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("New Time Block") { model.newBlock() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Task") { model.newTask() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Plan") {
            Button("Plan Today…") { model.morningPlanningPresented = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Plan My Day…") { model.planDayPresented = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Plan My Week…") { model.planWeekPresented = true }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Review Day…") { model.reviewPresented = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Reflow Day…") { model.reflowPresented = true }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Start Focus Timer…") { model.startFocus(taskID: nil, title: "Focus") }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Morning Ritual…") { model.morningRitualPresented = true }
            Button("Evening Ritual…") { model.eveningRitualPresented = true }
            Button("Journal…") { model.journalPresented = true }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Templates…") { model.templatesPresented = true }
            Button("Recalibrate…") { model.calibrationPresented = true }
            Divider()
            Button("Go to Today") { model.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Previous") { model.goBackward() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next") { model.goForward() }
                .keyboardShortcut("]", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(AppModel.Screen.allCases.filter { $0.shortcut != nil }) { screen in
                Button(screen.title) { model.screen = screen }
                    .keyboardShortcut(screen.shortcut ?? "0", modifiers: .command)
            }
            Divider()
        }
    }
}
#endif

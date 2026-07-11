import SwiftUI

@main
struct ChronosApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var service = EventKitService()
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(service)
                .environmentObject(profileStore)
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
                .frame(width: 480, height: 620)
                .preferredColorScheme(.dark)
        }
        #else
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(service)
                .environmentObject(profileStore)
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
            Button("Plan My Day…") { model.planDayPresented = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
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

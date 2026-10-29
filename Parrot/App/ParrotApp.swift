import SwiftUI

@main
struct ParrotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ParrotStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Parrot History", id: WindowID.history) {
            HistoryView()
                .environment(store)
        }
        .defaultSize(width: 560, height: 520)
        .defaultPosition(.center)

        Window("Parrot Calls", id: WindowID.calls) {
            CallsView()
                .environment(store)
        }
        .defaultSize(width: 820, height: 600)
        .defaultPosition(.center)

        Window("Parrot Vocabulary", id: WindowID.vocabulary) {
            VocabularyView()
                .environment(store)
        }
        .defaultSize(width: 560, height: 440)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before SwiftUI builds the store: a reminder that launched Parrot is handed to us now, and
        // waiting until the menu bar appears would drop the click that opened the app.
        MainActor.assumeIsolated { MeetingNotifications.shared.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updater.shared
    }
}

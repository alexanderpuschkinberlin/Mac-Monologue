import SwiftUI

@main
struct MacMonologueApp: App {
    @StateObject private var capture = CaptureController()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        Window("Mac-Monologue", id: "main") {
            ContentView(capture: capture)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear { updates.start(capture: capture) }
        }
        .windowResizability(.contentMinSize)
        .commands { AppCommands(capture: capture, updates: updates) }

        Settings {
            SettingsView(capture: capture, updates: updates)
        }

        // Always in the menu bar: the recorder has to be reachable while its
        // window is minimised and a presentation is in front.
        MenuBarExtra {
            MenuBarMenu(capture: capture, updates: updates, subtitles: capture.subtitles)
        } label: {
            MenuBarLabel(capture: capture)
        }
    }
}

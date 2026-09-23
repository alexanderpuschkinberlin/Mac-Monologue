import SwiftUI

@main
struct MacMonologueApp: App {
    @StateObject private var capture = CaptureController()

    var body: some Scene {
        Window("Mac-Monologue", id: "main") {
            ContentView(capture: capture)
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands { AppCommands(capture: capture) }

        // Always in the menu bar: the recorder has to be reachable while its
        // window is minimised and a presentation is in front.
        MenuBarExtra {
            MenuBarMenu(capture: capture)
        } label: {
            MenuBarLabel(capture: capture)
        }
    }
}

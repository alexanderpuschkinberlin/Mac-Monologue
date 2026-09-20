import SwiftUI

@main
struct MacMonologueApp: App {
    @StateObject private var capture = CaptureController()

    var body: some Scene {
        Window("Mac-Monologue", id: "main") {
            ContentView(capture: capture)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands { AppCommands(capture: capture) }
    }
}

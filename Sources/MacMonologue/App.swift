import SwiftUI

@main
struct MacMonologueApp: App {
    var body: some Scene {
        Window("Mac-Monologue", id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

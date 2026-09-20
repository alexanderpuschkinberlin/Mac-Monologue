import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Mac-Monologue")
                .font(.largeTitle)
            Text("Scaffold — capture comes next.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

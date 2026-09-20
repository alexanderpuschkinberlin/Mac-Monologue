import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let shortcuts: [(String, String)] = [
        ("Space", "Record, then pause, then resume — or play the finished clip"),
        ("⌘↩", "Finish the take"),
        ("⌫", "Discard the take"),
        ("⌘N", "Start a new recording"),
        ("⇧⌘R", "Reveal the recording in Finder"),
        ("?", "This list"),
        ("⌘Q", "Quit"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Self.shortcuts, id: \.0) { key, description in
                    GridRow {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 44, alignment: .leading)
                        Text(description)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

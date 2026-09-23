import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var toggleShortcut: Shortcut = .defaultToggle
    var finishShortcut: Shortcut = .defaultFinish

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

            Text("From any app — while presenting")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(toggleShortcut.displayString)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 64, alignment: .leading)
                    Text("Record, pause, resume")
                }
                GridRow {
                    Text(finishShortcut.displayString)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 64, alignment: .leading)
                    Text("Finish the take")
                }
            }

            Text("In the Mac-Monologue window")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Self.shortcuts, id: \.0) { key, description in
                    GridRow {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 64, alignment: .leading)
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

import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var toggleShortcut: Shortcut = .defaultToggle
    var finishShortcut: Shortcut = .defaultFinish

    private static let shortcuts: [(String, String)] = [
        ("Space", String(localized: "Record, then pause, then resume — or play the finished clip")),
        ("⌘↩", String(localized: "Finish the take")),
        ("⌫", String(localized: "Discard the take")),
        ("⌘N", String(localized: "Start a new recording")),
        ("⇧⌘R", String(localized: "Reveal the recording in Finder")),
        ("?", String(localized: "This list")),
        ("⌘Q", String(localized: "Quit")),
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

#if DEBUG
#Preview { HelpSheet() }
#endif

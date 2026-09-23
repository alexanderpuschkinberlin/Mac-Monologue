import AppKit
import Carbon.HIToolbox
import SwiftUI

/// "Change…" → press the new combination → done. Esc cancels.
struct ShortcutRecorderButton: View {
    @Binding var shortcut: Shortcut
    let defaultShortcut: Shortcut
    /// While recording, the global shortcuts are switched off, so pressing the
    /// current combination records it instead of starting a take.
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(isRecording ? "Press the new shortcut…" : "Change…") {
                    isRecording ? stop() : start()
                }
                if !isRecording, shortcut != defaultShortcut {
                    Button("Reset") { shortcut = defaultShortcut }
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stop()
                } else if let recorded = Shortcut(event: event), recorded.isAcceptable {
                    shortcut = recorded
                    stop()
                } else {
                    hint = "Use at least two of ⌃ ⌥ ⇧ ⌘ together with one key, "
                        + "so the shortcut cannot go off while typing."
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}

import AppKit
import Foundation

/// Quits this copy of the app and opens it again once it has fully exited.
///
/// Not by launching a second instance first: for a moment both would run, and
/// the new one could not register the global shortcuts the old one still held.
/// A small detached shell waits for this process to be gone, then opens the app
/// — which, after an update, is the new version at the same path.
@MainActor
enum Relauncher {
    static func relaunch(at bundleURL: URL = Bundle.main.bundleURL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Waits up to 30 s. If this instance is still alive by then — its quit
        // was cancelled — it opens nothing, rather than a second copy.
        let script = """
            for i in $(/usr/bin/seq 150); do
              /bin/kill -0 \(pid) 2>/dev/null || { /usr/bin/open "$1"; exit 0; }
              /bin/sleep 0.2
            done
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The path travels as an argument, never spliced into the script.
        process.arguments = ["-c", script, "mac-monologue-relaunch", bundleURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            // Without the helper, quitting would just close the app for good.
            NSWorkspace.shared.open(bundleURL)
            return
        }
        NSApp.terminate(nil)
    }
}

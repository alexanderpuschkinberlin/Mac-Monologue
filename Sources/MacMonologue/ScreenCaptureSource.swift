import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// A screen that can be recorded.
struct DisplayOption: Identifiable, Hashable, Sendable {
    let id: CGDirectDisplayID
    var name: String
    let pixelWidth: Int
    let pixelHeight: Int
    var isAvailable = true

    var displayName: String { isAvailable ? name : "\(name) — unavailable" }
}

/// Starts, changes and stops the ScreenCaptureKit stream.
///
/// ScreenCaptureKit's objects are not `Sendable`, so they never leave this class:
/// they are only touched on `controlQueue` or inside ScreenCaptureKit's own
/// callbacks, which hop straight back onto it. `@unchecked Sendable` on that basis.
final class ScreenCaptureSource: NSObject, @unchecked Sendable {
    struct Settings: Equatable, Sendable {
        var displayID: CGDirectDisplayID
        var width: Int
        var height: Int
        var showsMouseClicks: Bool
        var capturesAudio: Bool
    }

    enum SourceError: LocalizedError {
        case noShareableContent
        case displayGone

        var errorDescription: String? {
            switch self {
            case .noShareableContent: "macOS did not allow the screen to be read."
            case .displayGone: "That screen is no longer connected."
            }
        }
    }

    private let controlQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.screen")
    private var stream: SCStream?
    private var current: Settings?
    private var generation = 0

    /// Called when the stream stops on its own — a display unplugged, or access
    /// revoked mid-take. Called on an arbitrary queue.
    var onUnexpectedStop: (@Sendable (String) -> Void)?

    /// All connected displays with their true pixel size, which is what the canvas
    /// is derived from — `SCDisplay`'s own width and height are in points.
    static func fetchDisplays(completion: @escaping @Sendable (Result<[DisplayOption], Error>) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content else {
                completion(.failure(error ?? SourceError.noShareableContent))
                return
            }
            let displays = content.displays.map { display -> DisplayOption in
                let mode = CGDisplayCopyDisplayMode(display.displayID)
                return DisplayOption(
                    id: display.displayID,
                    name: "Display",
                    pixelWidth: mode?.pixelWidth ?? display.width,
                    pixelHeight: mode?.pixelHeight ?? display.height
                )
            }
            completion(.success(displays))
        }
    }

    /// Starts the stream with these settings, or stops it for nil. A call made
    /// while an earlier one is still starting supersedes it.
    func apply(
        _ settings: Settings?,
        output: CaptureRouter,
        outputQueue: DispatchQueue,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        controlQueue.async { [self] in
            generation += 1
            let token = generation

            if settings == current, stream != nil {
                completion(nil)
                return
            }
            stopCurrent()
            guard let settings else {
                completion(nil)
                return
            }

            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                nonisolated(unsafe) let content = content
                self.controlQueue.async {
                    guard token == self.generation else { return }
                    guard let content else {
                        completion(error ?? SourceError.noShareableContent)
                        return
                    }
                    guard let display = content.displays.first(where: { $0.displayID == settings.displayID }) else {
                        completion(SourceError.displayGone)
                        return
                    }
                    self.start(settings, display: display, content: content, output: output,
                               outputQueue: outputQueue, token: token, completion: completion)
                }
            }
        }
    }

    // MARK: - Internals (controlQueue)

    private func start(
        _ settings: Settings,
        display: SCDisplay,
        content: SCShareableContent,
        output: CaptureRouter,
        outputQueue: DispatchQueue,
        token: Int,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        // Leave Mac-Monologue itself out of the picture — otherwise its own window,
        // showing a live preview of the screen, would be recorded showing itself.
        let ownProcess = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownProcess, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = settings.width
        configuration.height = settings.height
        configuration.scalesToFit = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.showMouseClicks = settings.showsMouseClicks
        configuration.capturesAudio = settings.capturesAudio
        configuration.sampleRate = AudioMixerCore.sampleRate
        configuration.channelCount = 2
        // A finished take playing back must never feed into the next one.
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
            if settings.capturesAudio {
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: outputQueue)
            }
        } catch {
            completion(error)
            return
        }

        self.stream = stream
        current = settings

        nonisolated(unsafe) let started = stream
        started.startCapture { error in
            self.controlQueue.async {
                if error != nil, self.stream === started {
                    self.stream = nil
                    self.current = nil
                }
                if token == self.generation { completion(error) }
            }
        }
    }

    private func stopCurrent() {
        stream?.stopCapture(completionHandler: nil)
        stream = nil
        current = nil
    }
}

extension ScreenCaptureSource: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        nonisolated(unsafe) let stopped = stream
        controlQueue.async {
            guard self.stream === stopped else { return }
            self.stream = nil
            self.current = nil
            self.onUnexpectedStop?(TakeRecorder.describe(error))
        }
    }
}

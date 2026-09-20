import AVFoundation
import AppKit
import Combine
import Foundation

/// The seven states the whole UI hangs off.
///
/// `finishing` is a real state rather than a spinner: the HEVC flush is not
/// instant, and keystrokes during it are how a file gets corrupted.
enum RecorderState: Equatable {
    case needsAccess
    case unavailable
    case ready
    case recording
    case paused
    case finishing
    case preview

    var label: String {
        switch self {
        case .needsAccess: "Access needed"
        case .unavailable: "Unavailable"
        case .ready: "Ready"
        case .recording: "Recording"
        case .paused: "Paused"
        case .finishing: "Finishing"
        case .preview: "Preview"
        }
    }
}

/// A selectable capture device. `isAvailable == false` means it was remembered
/// from a previous launch but is not currently plugged in.
struct DeviceOption: Identifiable, Hashable {
    static let noAudioID = "__no_audio__"

    let id: String
    let name: String
    var isAvailable: Bool = true

    var displayName: String { isAvailable ? name : "\(name) — unavailable" }

    static let noAudio = DeviceOption(id: noAudioID, name: "No audio")
}

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var state: RecorderState = .ready
    @Published private(set) var cameras: [DeviceOption] = []
    @Published private(set) var microphones: [DeviceOption] = [.noAudio]
    @Published private(set) var formatSummary: String = ""
    @Published private(set) var banner: String?
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var audioLevel: Float = AudioLevelMeter.floorDB
    @Published private(set) var audioPeak: Float = AudioLevelMeter.floorDB
    @Published private(set) var isClipping = false
    @Published private(set) var lastRecordingURL: URL?

    /// Locked for the whole take, including while paused.
    @Published var selectedCameraID: String? {
        didSet {
            guard selectedCameraID != oldValue else { return }
            DevicePreferences.cameraID = selectedCameraID
            reconfigure()
        }
    }

    @Published var selectedMicrophoneID: String? {
        didSet {
            guard selectedMicrophoneID != oldValue else { return }
            DevicePreferences.microphoneID = selectedMicrophoneID
            reconfigure()
        }
    }

    var devicePickersLocked: Bool {
        state == .recording || state == .paused || state == .finishing
    }

    /// Only ever touched on `sessionQueue`, except when handed to the preview
    /// layer at view-construction time (AVCaptureVideoPreviewLayer takes a
    /// reference and does its own internal locking).
    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.session")
    /// Sample buffers are delivered here, separately from session configuration,
    /// so reconfiguring never stalls behind frame delivery.
    private let outputQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.output")

    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    private lazy var recorder = TakeRecorder(queue: outputQueue)

    /// Confined to `outputQueue`: only the meter's readings cross to the main actor.
    nonisolated(unsafe) private let meter = AudioLevelMeter()
    nonisolated(unsafe) private var lastMeterPublish: CFTimeInterval = 0

    /// Dimensions of the active capture format, handed to the encoder.
    private var activeDimensions = (width: 1920, height: 1080)

    /// Whether the configured session currently has an audio input.
    /// The `AVCaptureDeviceInput` objects themselves stay confined to
    /// `sessionQueue` — they are not Sendable and must not cross actors.
    @Published private(set) var hasAudio = false
    private var observers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    func start() {
        wireRecorder()
        selectedCameraID = DevicePreferences.cameraID
        selectedMicrophoneID = DevicePreferences.microphoneID ?? DeviceOption.noAudioID
        observeDeviceChanges()

        Task {
            let granted = await requestAccess()
            guard granted else {
                state = .needsAccess
                return
            }
            refreshDevices()
            reconfigure()
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Permissions

    private func requestAccess() async -> Bool {
        let video = await Self.authorize(.video)
        // Microphone access is requested up front too: asking mid-take, after the
        // user has already started talking, is worse than asking once at launch.
        _ = await Self.authorize(.audio)
        return video
    }

    private static func authorize(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    var cameraAccessDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
            || AVCaptureDevice.authorizationStatus(for: .video) == .restricted
    }

    var microphoneAccessDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
            || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted
    }

    // MARK: - Devices

    private func observeDeviceChanges() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshDevices()
                    self.handleDeviceChange()
                }
            }
            observers.append(token)
        }
    }

    private func refreshDevices() {
        let videoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        cameras = videoDevices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
        microphones = [.noAudio] + audioDevices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }

        // A remembered device that is gone stays in the list, greyed out, rather
        // than vanishing and taking the selection with it.
        if let id = selectedCameraID, !cameras.contains(where: { $0.id == id }) {
            cameras.append(DeviceOption(id: id, name: "Camera", isAvailable: false))
        }
        if let id = selectedMicrophoneID, id != DeviceOption.noAudioID,
           !microphones.contains(where: { $0.id == id }) {
            microphones.append(DeviceOption(id: id, name: "Microphone", isAvailable: false))
        }

        if selectedCameraID == nil { selectedCameraID = cameras.first(where: \.isAvailable)?.id }
    }

    private func handleDeviceChange() {
        guard state == .recording || state == .paused else {
            reconfigure()
            return
        }
        // Mid-take disconnects are routine on a Mac — Continuity Camera drops every
        // time the iPhone locks. Stopping and keeping the partial take is handled by
        // TakeRecorder; this only surfaces the banner.
        if let id = selectedCameraID, Self.device(id: id) == nil {
            banner = "The camera disconnected. The take has been stopped and kept."
        }
    }

    private static func device(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id)
    }

    // MARK: - Session configuration

    private func reconfigure() {
        guard !devicePickersLocked else { return }
        guard let cameraID = selectedCameraID, let camera = Self.device(id: cameraID) else {
            state = cameraAccessDenied ? .needsAccess : .unavailable
            formatSummary = ""
            return
        }

        let microphone = selectedMicrophoneID
            .flatMap { $0 == DeviceOption.noAudioID ? nil : Self.device(id: $0) }
        hasAudio = microphone != nil
        if microphone == nil {
            audioLevel = AudioLevelMeter.floorDB
            audioPeak = AudioLevelMeter.floorDB
            isClipping = false
        }


        let format = Self.bestFormat(for: camera)
        if let format {
            applyFormat(format, to: camera)
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            activeDimensions = (Int(d.width), Int(d.height))
            formatSummary = Self.summary(for: format, hasAudio: microphone != nil)
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            for input in self.session.inputs { self.session.removeInput(input) }

            if !self.session.outputs.contains(self.videoOutput), self.session.canAddOutput(self.videoOutput) {
                // macOS defaults this output to 4:2:2 (2vuy); the HEVC encoder
                // wants 4:2:0, and the writer will not convert it for us.
                let preferred = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                if self.videoOutput.availableVideoPixelFormatTypes.contains(preferred) {
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: preferred
                    ]
                }
                self.videoOutput.alwaysDiscardsLateVideoFrames = false
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self.recorder, queue: self.outputQueue)
            }
            if !self.session.outputs.contains(self.audioOutput), self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
                self.audioOutput.setSampleBufferDelegate(self.recorder, queue: self.outputQueue)
            }

            if let videoInput = try? AVCaptureDeviceInput(device: camera),
               self.session.canAddInput(videoInput) {
                self.session.addInput(videoInput)
            }

            if let microphone,
               let audioInput = try? AVCaptureDeviceInput(device: microphone),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
        }

        if state == .unavailable || state == .needsAccess { state = .ready }
        banner = nil
    }

    private func applyFormat(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(Self.targetFPS))
            if format.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= Self.targetFPS && Self.targetFPS <= $0.maxFrameRate
            }) {
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
        } catch {
            // Some virtual cameras refuse configuration; the session default is fine.
        }
    }

    // MARK: - Format selection

    static let targetFPS: Double = 30
    static let maxPixels = 1920 * 1080

    /// Best format capped at 1080p30.
    ///
    /// The Linux original picks the camera's *maximum* advertised resolution and
    /// refuses to downgrade, which is what produces its "encoding cannot keep up"
    /// failure. Capping instead: at 1080p a talking head is already the file you
    /// want, and 4K only buys enormous files you re-encode later.
    static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats
        guard !formats.isEmpty else { return nil }

        func pixels(_ format: AVCaptureDevice.Format) -> Int {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(d.width) * Int(d.height)
        }
        func supports30(_ format: AVCaptureDevice.Format) -> Bool {
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= targetFPS && targetFPS <= $0.maxFrameRate
            }
        }

        let underCap = formats.filter { pixels($0) <= maxPixels }
        let candidates = underCap.isEmpty ? formats : underCap

        // Prefer a format that actually does 30fps; among those, the largest.
        let thirty = candidates.filter(supports30)
        let pool = thirty.isEmpty ? candidates : thirty

        // If nothing fits under the cap, take the *smallest* the camera offers
        // rather than the largest — the cap exists to protect the encoder.
        return underCap.isEmpty
            ? pool.min(by: { pixels($0) < pixels($1) })
            : pool.max(by: { pixels($0) < pixels($1) })
    }

    // MARK: - Takes

    private func wireRecorder() {
        recorder.onStatusChange = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .recording: self.state = .recording
                case .paused: self.state = .paused
                case .finishing: self.state = .finishing
                case .idle: if self.state != .preview { self.state = .ready }
                }
            }
        }
        recorder.onDurationChange = { [weak self] seconds in
            Task { @MainActor in self?.elapsed = seconds }
        }
        recorder.onAudioBuffer = { [weak self] buffer in
            guard let self else { return }
            self.meter.consume(buffer)

            // Audio buffers arrive ~100×/s; the eye needs about 20.
            let now = CACurrentMediaTime()
            guard now - self.lastMeterPublish >= 0.05 else { return }
            self.lastMeterPublish = now

            let level = self.meter.level
            let peak = self.meter.peak
            let clipping = self.meter.isClipping
            Task { @MainActor in
                self.audioLevel = level
                self.audioPeak = peak
                self.isClipping = clipping
            }
        }
        recorder.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.banner = message
                self?.state = .ready
            }
        }
    }

    /// Space: record, then pause, then resume.
    func toggleRecording() {
        switch state {
        case .ready: startTake()
        // Preview gets clip playback in a later step; for now the button returns
        // to Ready rather than starting a take the moment you click it.
        case .preview: newRecording()
        case .recording: recorder.pause()
        case .paused: recorder.resume()
        case .needsAccess, .unavailable, .finishing: break
        }
    }

    private func startTake() {
        guard selectedCameraID.flatMap(Self.device(id:)) != nil else { return }
        lastRecordingURL = nil
        elapsed = 0
        banner = nil

        let configuration = TakeRecorder.Configuration(
            width: activeDimensions.width,
            height: activeDimensions.height,
            frameRate: Self.targetFPS,
            audioSettings: hasAudio ? recommendedAudioSettings() : nil
        )

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let clock = self.session.synchronizationClock
            self.recorder.start(configuration: configuration, sourceClock: clock)
        }
    }

    /// AVFoundation has no recommendation to give until the audio connection is
    /// live, so a take started moments after launch gets nil back — and without
    /// the fallback below that silently produces a file with no audio track at
    /// all. Started by hand, seconds later, it always works; which is precisely
    /// the kind of bug that ships.
    private func recommendedAudioSettings() -> [String: Any] {
        var settings: [String: Any] = [:]
        if let recommended = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) {
            for (key, value) in recommended {
                if let key = key as? String { settings[key] = value }
            }
        }
        guard settings[AVFormatIDKey] != nil else {
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ]
        }
        return settings
    }

    func finishTake() {
        guard state == .recording || state == .paused else { return }
        recorder.finish { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.lastRecordingURL = url
                    self.state = .preview
                case .failure(let error):
                    self.banner = TakeRecorder.describe(error)
                    self.state = .ready
                }
            }
        }
    }

    func discardTake() {
        if state == .recording || state == .paused {
            recorder.discard()
        }
        lastRecordingURL = nil
        elapsed = 0
        state = .ready
    }

    func newRecording() {
        lastRecordingURL = nil
        elapsed = 0
        if state == .preview { state = .ready }
    }

    func revealInFinder() {
        let url = lastRecordingURL
        let directory = TakeRecorder.recordingsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    static func summary(for format: AVCaptureDevice.Format, hasAudio: Bool) -> String {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(d.width) × \(d.height) · up to \(Int(targetFPS)) fps"
    }
}

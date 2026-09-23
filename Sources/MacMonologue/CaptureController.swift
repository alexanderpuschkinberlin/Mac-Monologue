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
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published var isConfirmingDiscard = false
    @Published var isShowingHelp = false

    /// Locked for the whole take, including while paused.
    @Published var selectedCameraID: String? {
        didSet {
            guard selectedCameraID != oldValue else { return }
            if persistsPreferences { DevicePreferences.cameraID = selectedCameraID }
            reconfigure()
        }
    }

    @Published var selectedMicrophoneID: String? {
        didSet {
            guard selectedMicrophoneID != oldValue else { return }
            if persistsPreferences { DevicePreferences.microphoneID = selectedMicrophoneID }
            reconfigure()
        }
    }

    /// Whether the saved file is mirrored. The live preview in camera mode is
    /// always mirrored — that is what makes moving around in it feel natural — so
    /// this decides only what the file looks like. In screen mode it applies to
    /// the bubble alone: screen content is never mirrored.
    @Published var mirrorsRecording = false {
        didSet {
            guard mirrorsRecording != oldValue else { return }
            if persistsPreferences { DevicePreferences.mirrorsRecording = mirrorsRecording }
            configureRouter()
        }
    }

    // MARK: Screen mode

    @Published var mode: CaptureMode = .camera {
        didSet {
            guard mode != oldValue else { return }
            if persistsPreferences { DevicePreferences.mode = mode }
            // macOS shows its prompt only the first time; afterwards this is a no-op.
            if mode == .screenAndCamera, !ScreenAccess.isGranted { ScreenAccess.request() }
            reconfigure()
        }
    }

    @Published private(set) var displays: [DisplayOption] = []

    @Published var selectedDisplayID: CGDirectDisplayID? {
        didSet {
            guard selectedDisplayID != oldValue else { return }
            if persistsPreferences, let id = selectedDisplayID,
               let display = displays.first(where: { $0.id == id && $0.isAvailable }) {
                DevicePreferences.displayID = id
                DevicePreferences.displayName = display.name
            }
            reconfigure()
        }
    }

    @Published var bubbleCorner: BubbleCorner = .bottomTrailing {
        didSet {
            guard bubbleCorner != oldValue else { return }
            if persistsPreferences { DevicePreferences.bubbleCorner = bubbleCorner }
            configureRouter()
        }
    }

    @Published var bubbleSize: BubbleSize = .medium {
        didSet {
            guard bubbleSize != oldValue else { return }
            if persistsPreferences { DevicePreferences.bubbleSize = bubbleSize }
            configureRouter()
        }
    }

    @Published private(set) var screenAccess: ScreenAccessState = .unknown
    @Published private(set) var isScreenCaptureRunning = false
    /// The recorded frame size in screen mode.
    @Published private(set) var canvasSize: CGSize = .zero

    /// Bumped after every session reconfiguration, so the preview can re-apply
    /// settings to a connection that may have been rebuilt.
    @Published private(set) var sessionGeneration = 0

    /// Whether a microphone is selected — which is also what the level meter
    /// shows. The `AVCaptureDeviceInput` objects themselves stay confined to
    /// `sessionQueue` — they are not Sendable and must not cross actors.
    @Published private(set) var hasAudio = false

    /// Whether the file gets an audio track at all. In screen mode it always does:
    /// system audio is recorded even with "No audio" chosen for the microphone.
    var recordsAudio: Bool { mode == .screenAndCamera || hasAudio }

    /// How the screen's clock related to the camera's in the last screen take.
    @Published private(set) var clockReading: ClockProbe.Reading?

    // MARK: Settings

    @Published var toggleShortcut: Shortcut = .defaultToggle {
        didSet {
            guard toggleShortcut != oldValue else { return }
            if persistsPreferences { DevicePreferences.toggleShortcut = toggleShortcut }
            registerHotkeys()
        }
    }

    @Published var finishShortcut: Shortcut = .defaultFinish {
        didSet {
            guard finishShortcut != oldValue else { return }
            if persistsPreferences { DevicePreferences.finishShortcut = finishShortcut }
            registerHotkeys()
        }
    }

    /// Shortcuts another app already owns, so registering them failed.
    @Published private(set) var unavailableShortcuts: [GlobalHotkeys.Action] = []

    @Published var autoMinimizes = true {
        didSet { if persistsPreferences { DevicePreferences.autoMinimizes = autoMinimizes } }
    }

    @Published var showsMouseClicks = true {
        didSet {
            guard showsMouseClicks != oldValue else { return }
            if persistsPreferences { DevicePreferences.showsMouseClicks = showsMouseClicks }
            if mode == .screenAndCamera { reconfigure() }
        }
    }

    private let hotkeys = GlobalHotkeys()
    private weak var mainWindow: NSWindow?
    private var minimizesWhenRecordingStarts = false
    private var minimizedForTake = false

    /// The hardware self-test must not overwrite the user's own settings.
    private var persistsPreferences: Bool { !SelfTest.isEnabled }

    var devicePickersLocked: Bool {
        state == .recording || state == .paused || state == .finishing
    }

    /// Whether a take can be started right now.
    var canRecord: Bool {
        switch mode {
        case .camera:
            return state != .needsAccess && state != .unavailable
        case .screenAndCamera:
            return screenAccess == .granted && isScreenCaptureRunning
        }
    }

    /// Only ever touched on `sessionQueue`, except when handed to the preview
    /// layer at view-construction time (AVCaptureVideoPreviewLayer takes a
    /// reference and does its own internal locking).
    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.session")
    /// Sample buffers are delivered here — camera, microphone and screen alike —
    /// separately from session configuration, so reconfiguring never stalls
    /// behind frame delivery.
    private let outputQueue: DispatchQueue

    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    private let recorder: TakeRecorder
    private let router: CaptureRouter
    private let screenSource = ScreenCaptureSource()

    /// Confined to `outputQueue`: only the meter's readings cross to the main actor.
    nonisolated(unsafe) private let meter = AudioLevelMeter()
    nonisolated(unsafe) private var lastMeterPublish: CFTimeInterval = 0

    /// Dimensions handed to the encoder: the camera's format, or the screen canvas.
    private var activeDimensions = (width: 1920, height: 1080)
    private var cameraDimensions = (width: 1920, height: 1080)
    private var cameraFrameRateSummary = ""

    private var observers: [NSObjectProtocol] = []
    private var screenRefreshGeneration = 0
    private var accessPolling: Task<Void, Never>?

    init() {
        let outputQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.output")
        let recorder = TakeRecorder(queue: outputQueue)
        self.outputQueue = outputQueue
        self.recorder = recorder
        self.router = CaptureRouter(queue: outputQueue, recorder: recorder)
    }

    // MARK: - Lifecycle

    func start() {
        wireRecorder()
        wireScreenSource()
        toggleShortcut = DevicePreferences.toggleShortcut
        finishShortcut = DevicePreferences.finishShortcut
        autoMinimizes = DevicePreferences.autoMinimizes
        showsMouseClicks = DevicePreferences.showsMouseClicks
        registerHotkeys()
        mirrorsRecording = DevicePreferences.mirrorsRecording
        bubbleCorner = DevicePreferences.bubbleCorner
        bubbleSize = DevicePreferences.bubbleSize
        selectedDisplayID = DevicePreferences.displayID
        mode = DevicePreferences.mode
        configureRouter()
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
        accessPolling?.cancel()
        stopScreenCapture()
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
        // A monitor plugged in or out changes which screens can be recorded.
        let screens = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .screenAndCamera, !self.devicePickersLocked else { return }
                self.refreshScreenCapture()
            }
        }
        observers.append(screens)
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
        guard let id = selectedCameraID, Self.device(id: id) == nil else { return }

        // Mid-take disconnects are routine on a Mac — Continuity Camera drops every
        // time the iPhone locks.
        switch mode {
        case .camera:
            // Nothing left to record: finish, and keep what there is.
            banner = "The camera disconnected. The take has been stopped and kept."
            finishTake()
        case .screenAndCamera:
            // The presentation matters more than the bubble: keep recording.
            banner = "The camera disconnected. The screen keeps recording without the bubble."
        }
    }

    private static func device(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id)
    }

    // MARK: - Session configuration

    private func reconfigure() {
        guard !devicePickersLocked else { return }

        let camera = selectedCameraID.flatMap(Self.device(id:))
        let microphone = selectedMicrophoneID
            .flatMap { $0 == DeviceOption.noAudioID ? nil : Self.device(id: $0) }
        hasAudio = microphone != nil
        if microphone == nil {
            audioLevel = AudioLevelMeter.floorDB
            audioPeak = AudioLevelMeter.floorDB
            isClipping = false
        }

        if let camera, let format = Self.bestFormat(for: camera) {
            applyFormat(format, to: camera)
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            cameraDimensions = (Int(d.width), Int(d.height))
        }

        configureSession(camera: camera, microphone: microphone)
        banner = nil

        switch mode {
        case .camera:
            stopScreenCapture()
            guard camera != nil else {
                state = cameraAccessDenied ? .needsAccess : .unavailable
                formatSummary = ""
                configureRouter()
                return
            }
            activeDimensions = cameraDimensions
            formatSummary = "\(cameraDimensions.width) × \(cameraDimensions.height) · up to \(Int(Self.targetFPS)) fps"

        case .screenAndCamera:
            if camera == nil, !cameraAccessDenied {
                banner = "No camera available — the screen will be recorded without the bubble."
            }
            refreshScreenCapture()
        }

        if state == .unavailable || state == .needsAccess { state = .ready }
        configureRouter()
    }

    private func configureSession(camera: AVCaptureDevice?, microphone: AVCaptureDevice?) {
        let router = self.router
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Registered first so it runs last: after the commit below.
            defer { Task { @MainActor in self.sessionGeneration &+= 1 } }
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
                self.videoOutput.setSampleBufferDelegate(router, queue: self.outputQueue)
            }
            if !self.session.outputs.contains(self.audioOutput), self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
                self.audioOutput.setSampleBufferDelegate(router, queue: self.outputQueue)
            }

            if let camera,
               let videoInput = try? AVCaptureDeviceInput(device: camera),
               self.session.canAddInput(videoInput) {
                self.session.addInput(videoInput)
            }

            if let microphone,
               let audioInput = try? AVCaptureDeviceInput(device: microphone),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
        }
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

    // MARK: - Screen capture

    /// Finds the screens, picks one, and (re)starts the stream for it.
    private func refreshScreenCapture() {
        screenRefreshGeneration += 1
        let generation = screenRefreshGeneration

        guard ScreenAccess.isGranted else {
            screenAccess = .denied
            stopScreenCapture()
            formatSummary = ""
            pollForScreenAccess()
            return
        }

        ScreenCaptureSource.fetchDisplays { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.screenRefreshGeneration,
                      self.mode == .screenAndCamera, !self.devicePickersLocked else { return }
                switch result {
                case .failure:
                    // Preflight says yes, ScreenCaptureKit says no: granted in System
                    // Settings, but only a freshly started app gets to see the screen.
                    self.screenAccess = .needsRelaunch
                    self.stopScreenCapture()
                    self.formatSummary = ""
                case .success(let found):
                    self.screenAccess = .granted
                    self.accessPolling?.cancel()
                    self.startScreenCapture(on: self.named(found), generation: generation)
                }
            }
        }
    }

    private func startScreenCapture(on found: [DisplayOption], generation: Int) {
        var options = found
        var chosen = selectedDisplayID.flatMap { id in found.first { $0.id == id } }

        if chosen == nil, let name = DevicePreferences.displayName,
           let byName = found.first(where: { $0.name == name }) {
            // The same monitor, re-plugged under a new ID.
            chosen = byName
        }
        if chosen == nil, let remembered = selectedDisplayID ?? DevicePreferences.displayID {
            // A remembered screen that is not connected stays in the list, greyed
            // out — recording a different screen than intended is the worse outcome.
            options.append(DisplayOption(id: remembered, name: DevicePreferences.displayName ?? "Screen",
                                         pixelWidth: 0, pixelHeight: 0, isAvailable: false))
        }
        if chosen == nil, selectedDisplayID == nil, DevicePreferences.displayID == nil {
            chosen = found.first { $0.id == CGMainDisplayID() } ?? found.first
        }

        displays = options
        if let chosen, selectedDisplayID != chosen.id {
            selectedDisplayID = chosen.id        // re-enters via didSet → reconfigure
            return
        }

        guard let chosen else {
            banner = "The screen you chose last time is not connected. Pick another one."
            stopScreenCapture()
            formatSummary = ""
            return
        }

        let canvas = ScreenCanvas.size(forDisplayWidth: chosen.pixelWidth, height: chosen.pixelHeight)
        canvasSize = CGSize(width: canvas.width, height: canvas.height)
        activeDimensions = canvas
        formatSummary = "\(canvas.width) × \(canvas.height) · \(Int(Self.targetFPS)) fps · Screen + Camera"
        configureRouter()

        let settings = ScreenCaptureSource.Settings(
            displayID: chosen.id, width: canvas.width, height: canvas.height,
            showsMouseClicks: showsMouseClicks, capturesAudio: true
        )
        screenSource.apply(settings, output: router, outputQueue: outputQueue) { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.screenRefreshGeneration else { return }
                if let error {
                    self.isScreenCaptureRunning = false
                    self.banner = "The screen could not be recorded: \(TakeRecorder.describe(error))"
                } else {
                    self.isScreenCaptureRunning = true
                }
            }
        }
    }

    private func stopScreenCapture() {
        isScreenCaptureRunning = false
        screenSource.apply(nil, output: router, outputQueue: outputQueue) { _ in }
    }

    private func wireScreenSource() {
        screenSource.onUnexpectedStop = { [weak self] reason in
            Task { @MainActor in
                guard let self else { return }
                self.isScreenCaptureRunning = false
                if self.state == .recording || self.state == .paused {
                    self.banner = "The screen being recorded went away. The take has been stopped and kept."
                    self.finishTake()
                } else {
                    self.banner = "Screen recording stopped: \(reason)"
                }
            }
        }
    }

    /// Screen names as the user knows them, from AppKit — ScreenCaptureKit has none.
    private func named(_ found: [DisplayOption]) -> [DisplayOption] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return found.enumerated().map { index, display in
            var display = display
            display.name = names[display.id] ?? "Screen \(index + 1)"
            return display
        }
    }

    /// Picks up a grant made in System Settings while the app is open, where macOS
    /// allows that without a relaunch.
    private func pollForScreenAccess() {
        guard accessPolling == nil || accessPolling?.isCancelled == true else { return }
        accessPolling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.mode == .screenAndCamera else { return }
                if ScreenAccess.isGranted {
                    self.accessPolling = nil
                    self.refreshScreenCapture()
                    return
                }
            }
        }
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(ScreenAccess.settingsURL)
    }

    func relaunch() {
        ScreenAccess.relaunch()
    }

    // MARK: - Format selection

    static let targetFPS: Double = 30
    static let maxPixels = 1920 * 1080

    /// Best format capped at 1080p30.
    ///
    /// omacom/monologue picks the camera's *maximum* advertised resolution and
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

    private func configureRouter() {
        router.configure(CaptureRouter.Configuration(
            mode: mode,
            mirrorsRecording: mirrorsRecording,
            bubble: BubbleLayout(corner: bubbleCorner, size: bubbleSize),
            canvasWidth: mode == .screenAndCamera ? Int(canvasSize.width) : 0,
            canvasHeight: mode == .screenAndCamera ? Int(canvasSize.height) : 0
        ))
    }

    func attachPreview(_ sink: PreviewSink?) {
        router.setPreviewSink(sink)
    }

    // MARK: - Control from anywhere

    private func registerHotkeys() {
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleRecording:
                // From outside the app, Space-like overloading would be a
                // surprise: a global press never starts playback of a clip.
                if self.state == .preview { self.newRecording() }
                self.toggleRecording()
            case .finish:
                self.finishTake()
            }
        }
        hotkeys.register([.toggleRecording: toggleShortcut, .finish: finishShortcut])
        unavailableShortcuts = hotkeys.failed
    }

    func setMainWindow(_ window: NSWindow?) {
        mainWindow = window
    }

    func showMainWindow() {
        NSApp.activate()
        if let mainWindow {
            if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    /// In screen mode the window would sit over what is being recorded — it is
    /// already left out of the recording itself, but it still covers the slides
    /// for the person presenting.
    private func minimizeForTakeIfNeeded() {
        guard minimizesWhenRecordingStarts else { return }
        minimizesWhenRecordingStarts = false
        guard let mainWindow, !mainWindow.isMiniaturized else { return }
        minimizedForTake = true
        mainWindow.miniaturize(nil)
    }

    private func restoreAfterTake() {
        minimizesWhenRecordingStarts = false
        guard minimizedForTake else { return }
        minimizedForTake = false
        showMainWindow()
    }

    private func wireRecorder() {
        recorder.onStatusChange = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .recording:
                    self.state = .recording
                    self.minimizeForTakeIfNeeded()
                case .paused: self.state = .paused
                case .finishing: self.state = .finishing
                case .idle:
                    if self.state != .preview { self.state = .ready }
                    self.restoreAfterTake()
                }
            }
        }
        recorder.onDurationChange = { [weak self] seconds in
            Task { @MainActor in self?.elapsed = seconds }
        }
        router.onMicrophoneBuffer = { [weak self] buffer in
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
        router.onClockReading = { [weak self] reading in
            Task { @MainActor in
                guard let self else { return }
                self.clockReading = reading
                if reading.verdict == .unrelated {
                    self.banner = "System audio could not be synchronised with the camera and may drift."
                }
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
        // Space is overloaded in preview: it plays the clip rather than starting
        // a take you did not ask for.
        case .preview: togglePlayback()
        case .recording: recorder.pause()
        case .paused: recorder.resume()
        case .needsAccess, .unavailable, .finishing: break
        }
    }

    private func startTake() {
        guard canRecord else { return }
        lastRecordingURL = nil
        elapsed = 0
        banner = nil

        let screenMode = mode == .screenAndCamera
        let configuration = TakeRecorder.Configuration(
            width: activeDimensions.width,
            height: activeDimensions.height,
            frameRate: Self.targetFPS,
            // Screen mode writes the mixer's output — mono 48 kHz Float32 — so it
            // gets settings for exactly that, not a recommendation made for the
            // microphone's own format.
            audioSettings: screenMode ? Self.mixedAudioSettings : (hasAudio ? recommendedAudioSettings() : nil),
            averageBitRate: screenMode ? TakeRecorder.screenBitRate : TakeRecorder.cameraBitRate
        )
        clockReading = nil
        router.prepareTake(microphonePresent: hasAudio)
        minimizesWhenRecordingStarts = screenMode && autoMinimizes && !SelfTest.isEnabled

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let clock = self.session.synchronizationClock
            self.recorder.start(configuration: configuration, sourceClock: clock)
        }
    }

    static let mixedAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: AudioMixerCore.sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000,
    ]

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
                    self.preparePlayer(for: url)
                    self.state = .preview
                case .failure(let error):
                    self.banner = TakeRecorder.describe(error)
                    self.state = .ready
                }
            }
        }
    }

    // MARK: - Playback

    private func preparePlayer(for url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        isPlaying = false

        let token = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.player?.seek(to: .zero)
            }
        }
        observers.append(token)
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if player.currentTime() >= (player.currentItem?.duration ?? .zero) {
                player.seek(to: .zero)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private func tearDownPlayer() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Discard

    /// Always confirms. Discarding is the one irreversible-feeling action here,
    /// even though a finished take goes to the Trash rather than vanishing.
    func requestDiscard() {
        guard state == .recording || state == .paused || state == .preview else { return }
        // The confirmation lives in the main window; it must be visible to answer.
        showMainWindow()
        isConfirmingDiscard = true
    }

    func discardTake() {
        isConfirmingDiscard = false

        if state == .recording || state == .paused {
            // Nothing has reached ~/Movies yet: this is a temp-file delete.
            recorder.discard()
        } else if state == .preview, let url = lastRecordingURL {
            // Finished takes go to the Trash, so Finder's Put Back works.
            tearDownPlayer()
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }

        tearDownPlayer()
        lastRecordingURL = nil
        elapsed = 0
        state = .ready
    }

    func newRecording() {
        tearDownPlayer()
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
}

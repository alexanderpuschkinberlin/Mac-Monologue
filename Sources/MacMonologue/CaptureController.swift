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
    /// The selected camera is connected but has sent no picture for a while —
    /// typically an iPhone that is locked away or out of reach.
    @Published private(set) var cameraIsSilent = false
    /// Another camera to offer while the selected one is silent.
    @Published private(set) var alternativeCamera: DeviceOption?
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

    /// Resolution and bitrate of the next take. Changing it rebuilds the screen
    /// canvas, so it is locked during a take like the device pickers.
    @Published var videoQuality: VideoQuality = .standard {
        didSet {
            guard videoQuality != oldValue else { return }
            if persistsPreferences { DevicePreferences.videoQuality = videoQuality }
            reconfigure()
        }
    }

    // MARK: Keeping you in frame

    /// How the selected camera can follow a face, if at all.
    enum Framing: Equatable {
        case unavailable
        /// The camera does it itself — an iPhone, a Studio Display.
        case centerStage
        /// Done here, by zooming in and moving the window.
        case software
    }

    @Published private(set) var framing: Framing = .unavailable

    /// The user's choice for this camera; off until they turn it on.
    @Published var keepsMeInFrame = false {
        didSet {
            guard keepsMeInFrame != oldValue, !isLoadingFramingChoice else { return }
            if persistsPreferences, let id = selectedCameraID {
                DevicePreferences.setKeepsInFrame(keepsMeInFrame, cameraID: id)
            }
            applyFraming()
        }
    }
    private var isLoadingFramingChoice = false
    private var centerStageObserver: CenterStageObserver?

    /// Whether frames are cropped here — and the preview must show the crop.
    var followsFaceInSoftware: Bool {
        framing == .software && keepsMeInFrame && mode.usesCamera
    }

    // MARK: Screen mode

    @Published var mode: CaptureMode = .camera {
        didSet {
            guard mode != oldValue else { return }
            if persistsPreferences { DevicePreferences.mode = mode }
            // macOS shows its prompt only the first time; afterwards this is a no-op.
            if captureBegun, mode.recordsScreen, !ScreenAccess.isGranted { ScreenAccess.request() }
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
    var recordsAudio: Bool { mode.recordsScreen || hasAudio }

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
            if mode.recordsScreen { reconfigure() }
        }
    }

    @Published var launchMode: LaunchMode = .lastUsed {
        didSet { if persistsPreferences { DevicePreferences.launchMode = launchMode } }
    }

    @Published var isShowingOnboarding = false

    /// Nothing touches a camera or microphone before this — on a first launch not
    /// until the welcome steps have said why, so macOS never asks out of the blue.
    private var captureBegun = false

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
        case .screen, .screenAndCamera:
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
    private var cameraWatch: Task<Void, Never>?

    /// Subtitles for finished takes, made in the background.
    let subtitles = SubtitleCenter()

    /// How far the camera's picture is turned to stand upright — an iPhone on a
    /// stand in portrait, or upside down, reports it; a built-in camera stays at 0.
    @Published private(set) var cameraRotationAngle: CGFloat = 0
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    /// How long the selected camera may stay silent before the window says so.
    static let cameraSilenceSeconds: CFTimeInterval = 5

    init() {
        let outputQueue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.output")
        let recorder = TakeRecorder(queue: outputQueue)
        self.outputQueue = outputQueue
        self.recorder = recorder
        self.router = CaptureRouter(queue: outputQueue, recorder: recorder)
    }

    // MARK: - Lifecycle

    func start() {
        subtitles.onFinished = { [weak self] video in
            // The file was replaced; show the one with subtitles.
            guard let self, self.state == .preview, self.lastRecordingURL == video else { return }
            self.tearDownPlayer()
            self.preparePlayer(for: video)
        }
        wireRecorder()
        wireScreenSource()
        toggleShortcut = DevicePreferences.toggleShortcut
        finishShortcut = DevicePreferences.finishShortcut
        autoMinimizes = DevicePreferences.autoMinimizes
        showsMouseClicks = DevicePreferences.showsMouseClicks
        registerHotkeys()
        mirrorsRecording = DevicePreferences.mirrorsRecording
        videoQuality = DevicePreferences.videoQuality
        bubbleCorner = DevicePreferences.bubbleCorner
        bubbleSize = DevicePreferences.bubbleSize
        selectedDisplayID = DevicePreferences.displayID
        launchMode = DevicePreferences.launchMode
        switch launchMode {
        case .lastUsed: mode = DevicePreferences.mode
        case .camera: mode = .camera
        case .screen: mode = .screen
        case .screenAndCamera: mode = .screenAndCamera
        }
        configureRouter()
        selectedCameraID = DevicePreferences.cameraID
        selectedMicrophoneID = DevicePreferences.microphoneID ?? DeviceOption.noAudioID
        observeDeviceChanges()

        if DevicePreferences.hasCompletedOnboarding || SelfTest.isEnabled {
            beginCapture()
        } else {
            isShowingOnboarding = true
        }
    }

    func showOnboarding() {
        showMainWindow()
        isShowingOnboarding = true
    }

    func completeOnboarding(relaunch: Bool) {
        if persistsPreferences { DevicePreferences.hasCompletedOnboarding = true }
        isShowingOnboarding = false
        if relaunch {
            ScreenAccess.relaunch()
        } else {
            beginCapture()
        }
    }

    private func beginCapture() {
        guard !captureBegun else { return }
        captureBegun = true

        Task {
            let granted = await requestAccess()
            // Recording just the screen needs no camera.
            guard granted || mode == .screen else {
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
        cameraWatch?.cancel()
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
                guard let self, self.mode.recordsScreen, !self.devicePickersLocked else { return }
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
        case .screen:
            break
        }
    }

    private static func device(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id)
    }

    // MARK: - Session configuration

    private func reconfigure() {
        guard captureBegun, !devicePickersLocked else { return }

        let camera = mode.usesCamera ? selectedCameraID.flatMap(Self.device(id:)) : nil
        let microphone = selectedMicrophoneID
            .flatMap { $0 == DeviceOption.noAudioID ? nil : Self.device(id: $0) }
        hasAudio = microphone != nil
        if microphone == nil {
            audioLevel = AudioLevelMeter.floorDB
            audioPeak = AudioLevelMeter.floorDB
            isClipping = false
        }

        followRotation(of: camera)
        if let camera, let format = Self.bestFormat(for: camera) {
            applyFormat(format, to: camera)
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            cameraDimensions = Self.isSideways(cameraRotationAngle)
                ? (Int(d.height), Int(d.width))
                : (Int(d.width), Int(d.height))
        }

        loadFraming(for: camera)
        configureSession(camera: camera, microphone: microphone, rotationAngle: cameraRotationAngle)
        watchCamera(camera != nil)
        banner = nil

        switch mode {
        case .camera:
            stopScreenCapture()
            guard camera != nil, !cameraAccessDenied else {
                state = cameraAccessDenied ? .needsAccess : .unavailable
                formatSummary = ""
                configureRouter()
                return
            }
            activeDimensions = videoQuality.cameraSize(width: cameraDimensions.width, height: cameraDimensions.height)
            formatSummary = "\(activeDimensions.width) × \(activeDimensions.height) · up to \(Int(Self.targetFPS)) fps"
                + " · \(videoQuality.sizeLabel)"

        case .screenAndCamera:
            if camera == nil, !cameraAccessDenied {
                banner = "No camera available — the screen will be recorded without the bubble."
            }
            refreshScreenCapture()

        case .screen:
            refreshScreenCapture()
        }

        if state == .unavailable || state == .needsAccess { state = .ready }
        configureRouter()
    }

    /// What the camera can do to keep a face in frame, and what the user chose for it.
    private func loadFraming(for camera: AVCaptureDevice?) {
        if let camera {
            framing = camera.formats.contains(where: \.isCenterStageSupported) ? .centerStage : .software
        } else {
            framing = .unavailable
        }
        isLoadingFramingChoice = true
        keepsMeInFrame = camera.map { DevicePreferences.keepsInFrame(cameraID: $0.uniqueID) } ?? false
        isLoadingFramingChoice = false
        applyFraming()
    }

    private func applyFraming() {
        if framing == .centerStage {
            // Cooperative: the app sets it, and the user can still change it in
            // Control Center — which flows back into the switch.
            if AVCaptureDevice.centerStageControlMode != .cooperative {
                AVCaptureDevice.centerStageControlMode = .cooperative
            }
            if AVCaptureDevice.isCenterStageEnabled != keepsMeInFrame {
                AVCaptureDevice.isCenterStageEnabled = keepsMeInFrame
            }
            if centerStageObserver == nil {
                centerStageObserver = CenterStageObserver { [weak self] enabled in
                    Task { @MainActor in
                        guard let self, self.framing == .centerStage, self.keepsMeInFrame != enabled else { return }
                        self.keepsMeInFrame = enabled
                    }
                }
            }
        }
        configureRouter()
    }

    /// Keeps the picture upright whichever way the camera stands. Read when the
    /// camera is chosen and whenever it is turned — but never applied mid-take:
    /// the file keeps the shape it started with, and the new angle applies to the
    /// next take.
    private func followRotation(of camera: AVCaptureDevice?) {
        guard let camera else {
            rotationObservation = nil
            rotationCoordinator = nil
            cameraRotationAngle = 0
            return
        }
        if rotationCoordinator?.device?.uniqueID != camera.uniqueID {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            rotationCoordinator = coordinator
            // Delivered on the main queue, as documented.
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                      options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.reconfigure() }
            }
        }
        cameraRotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
    }

    static func isSideways(_ angle: CGFloat) -> Bool {
        Int(angle.rounded()).quotientAndRemainder(dividingBy: 180).remainder.magnitude == 90
    }

    /// Continuity Camera can be listed as connected and still never deliver a
    /// frame. Rather than a black window, say so and offer another camera.
    private func watchCamera(_ isConfigured: Bool) {
        cameraWatch?.cancel()
        cameraIsSilent = false
        alternativeCamera = nil
        guard isConfigured else { return }
        let watchStarted = CACurrentMediaTime()
        cameraWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let lastFrame = max(self.router.lastCameraFrameTime, watchStarted)
                let silent = self.state == .ready
                    && CACurrentMediaTime() - lastFrame > Self.cameraSilenceSeconds
                guard silent != self.cameraIsSilent else { continue }
                self.cameraIsSilent = silent
                self.alternativeCamera = silent
                    ? self.cameras.first { $0.isAvailable && $0.id != self.selectedCameraID }
                    : nil
            }
        }
    }

    func useAlternativeCamera() {
        guard let alternativeCamera else { return }
        selectedCameraID = alternativeCamera.id
    }

    private func configureSession(camera: AVCaptureDevice?, microphone: AVCaptureDevice?,
                                  rotationAngle: CGFloat) {
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
                // Frames arrive already upright, so the recorder, the bubble and
                // the mirroring never need to know the camera was turned.
                if let connection = self.videoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
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
                      self.mode.recordsScreen, !self.devicePickersLocked else { return }
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

        let canvas = ScreenCanvas.size(forDisplayWidth: chosen.pixelWidth, height: chosen.pixelHeight,
                                       longEdge: videoQuality.screenLongEdge)
        canvasSize = CGSize(width: canvas.width, height: canvas.height)
        activeDimensions = canvas
        formatSummary = "\(canvas.width) × \(canvas.height) · \(Int(Self.targetFPS)) fps · \(videoQuality.sizeLabel)"
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
                guard let self, self.mode.recordsScreen else { return }
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
            canvasWidth: mode.recordsScreen ? Int(canvasSize.width) : 0,
            canvasHeight: mode.recordsScreen ? Int(canvasSize.height) : 0,
            followsFace: followsFaceInSoftware
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

    /// Switched off while a new shortcut is being recorded in Settings, so pressing
    /// the current combination records it rather than starting a take.
    func setHotkeysSuspended(_ suspended: Bool) {
        if suspended {
            hotkeys.unregisterAll()
        } else {
            registerHotkeys()
        }
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

        let screenMode = mode.recordsScreen
        let configuration = TakeRecorder.Configuration(
            width: activeDimensions.width,
            height: activeDimensions.height,
            frameRate: Self.targetFPS,
            // Screen mode writes the mixer's output — mono 48 kHz Float32 — so it
            // gets settings for exactly that, not a recommendation made for the
            // microphone's own format.
            audioSettings: screenMode ? Self.mixedAudioSettings(bitRate: videoQuality.audioBitRate)
                : (hasAudio ? recommendedAudioSettings(bitRate: videoQuality.audioBitRate) : nil),
            averageBitRate: videoQuality.videoBitRate
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

    static func mixedAudioSettings(bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioMixerCore.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
    }

    /// AVFoundation has no recommendation to give until the audio connection is
    /// live, so a take started moments after launch gets nil back — and without
    /// the fallback below that silently produces a file with no audio track at
    /// all. Started by hand, seconds later, it always works; which is precisely
    /// the kind of bug that ships.
    private func recommendedAudioSettings(bitRate: Int) -> [String: Any] {
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
                AVEncoderBitRateKey: bitRate,
            ]
        }
        // The recommendation is sized for the microphone, not for the step the
        // user chose; only the rate is overridden.
        settings.removeValue(forKey: AVEncoderBitRatePerChannelKey)
        settings.removeValue(forKey: AVEncoderBitRateStrategyKey)
        settings[AVEncoderBitRateKey] = bitRate
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
                    if self.recordsAudio { self.subtitles.start(for: url) }
                    // The camera may have been turned during the take.
                    if let turned = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
                       turned != self.cameraRotationAngle {
                        self.reconfigure()
                    }
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
            subtitles.discard(url)
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

/// Center Stage's on/off is a class property; only Objective-C style KVO on the
/// class object sees it change, which is what happens when the user flips it in
/// Control Center.
private final class CenterStageObserver: NSObject {
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
        super.init()
        AVCaptureDevice.self.addObserver(self, forKeyPath: "centerStageEnabled", options: [.new], context: nil)
    }

    deinit {
        AVCaptureDevice.self.removeObserver(self, forKeyPath: "centerStageEnabled")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        onChange(AVCaptureDevice.isCenterStageEnabled)
    }
}

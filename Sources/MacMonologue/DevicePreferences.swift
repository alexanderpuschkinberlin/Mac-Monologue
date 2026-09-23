import CoreGraphics
import Foundation

/// Remembers the camera and microphone across launches, by unique device ID.
///
/// IDs rather than names: a remembered device that has disappeared is shown as
/// unavailable instead of silently falling back to another camera, which is how
/// you record three minutes into the wrong lens.
enum DevicePreferences {
    private static let cameraKey = "selectedCameraID"
    private static let microphoneKey = "selectedMicrophoneID"
    private static let mirrorsRecordingKey = "mirrorsRecording"
    private static let modeKey = "captureMode"
    private static let displayIDKey = "selectedDisplayID"
    private static let displayNameKey = "selectedDisplayName"
    private static let bubbleCornerKey = "bubbleCorner"
    private static let bubbleSizeKey = "bubbleSize"
    private static let toggleShortcutKey = "toggleShortcut"
    private static let finishShortcutKey = "finishShortcut"
    private static let autoMinimizesKey = "autoMinimizes"
    private static let showsMouseClicksKey = "showsMouseClicks"
    private static let completedOnboardingKey = "hasCompletedOnboarding"
    private static let launchModeKey = "launchMode"
    private static let checksForUpdatesKey = "checksForUpdatesAutomatically"
    private static let skippedUpdateKey = "skippedUpdateVersion"
    private static let lastUpdateCheckKey = "lastUpdateCheck"
    private static let videoQualityKey = "videoQuality"
    private static let keepsInFrameKey = "keepsInFrame"
    private static let subtitlesEnabledKey = "subtitlesEnabled"
    private static let spokenLanguageKey = "subtitleSpokenLanguage"
    private static let subtitleLanguagesKey = "subtitleLanguages"

    static var cameraID: String? {
        get { UserDefaults.standard.string(forKey: cameraKey) }
        set { UserDefaults.standard.set(newValue, forKey: cameraKey) }
    }

    /// `DeviceOption.noAudioID` is a legitimate stored value — the user chose "No audio".
    static var microphoneID: String? {
        get { UserDefaults.standard.string(forKey: microphoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: microphoneKey) }
    }

    /// Absent means off: the saved file reads the right way round by default.
    static var mirrorsRecording: Bool {
        get { UserDefaults.standard.bool(forKey: mirrorsRecordingKey) }
        set { UserDefaults.standard.set(newValue, forKey: mirrorsRecordingKey) }
    }

    static var mode: CaptureMode {
        get { UserDefaults.standard.string(forKey: modeKey).flatMap(CaptureMode.init) ?? .camera }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Kept together with the name: `CGDirectDisplayID` does not reliably identify
    /// an external monitor across being unplugged and plugged back in, its name does.
    static var displayID: CGDirectDisplayID? {
        get { (UserDefaults.standard.object(forKey: displayIDKey) as? Int).map { CGDirectDisplayID($0) } }
        set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: displayIDKey) }
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: displayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    /// Absent means the standard step — also for everyone updating from 0.3,
    /// whose takes were written at several times the size of any step.
    static var videoQuality: VideoQuality {
        get { UserDefaults.standard.string(forKey: videoQualityKey).flatMap(VideoQuality.init) ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: videoQualityKey) }
    }

    /// Per camera: following your face is a choice made for one lens, and off
    /// until made — an iPhone with Center Stage and a FaceTime camera zooming in
    /// software are not the same trade.
    static func keepsInFrame(cameraID: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: keepsInFrameKey) as? [String: Bool])?[cameraID] ?? false
    }

    static func setKeepsInFrame(_ keeps: Bool, cameraID: String) {
        var all = (UserDefaults.standard.dictionary(forKey: keepsInFrameKey) as? [String: Bool]) ?? [:]
        all[cameraID] = keeps
        UserDefaults.standard.set(all, forKey: keepsInFrameKey)
    }

    /// The main switch. Off keeps the languages chosen, for turning it back on.
    static var subtitlesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: subtitlesEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: subtitlesEnabledKey) }
    }

    static var spokenLanguage: SubtitleLanguage {
        get { UserDefaults.standard.string(forKey: spokenLanguageKey).flatMap(SubtitleLanguage.init) ?? .systemDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: spokenLanguageKey) }
    }

    /// Nothing chosen until the user chooses.
    static var subtitleLanguages: Set<SubtitleLanguage> {
        get { Set((UserDefaults.standard.stringArray(forKey: subtitleLanguagesKey) ?? []).compactMap(SubtitleLanguage.init)) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: subtitleLanguagesKey) }
    }

    static var bubbleCorner: BubbleCorner {
        get { UserDefaults.standard.string(forKey: bubbleCornerKey).flatMap(BubbleCorner.init) ?? .bottomTrailing }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bubbleCornerKey) }
    }

    static var bubbleSize: BubbleSize {
        get { UserDefaults.standard.string(forKey: bubbleSizeKey).flatMap(BubbleSize.init) ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bubbleSizeKey) }
    }

    static var toggleShortcut: Shortcut {
        get { shortcut(forKey: toggleShortcutKey) ?? .defaultToggle }
        set { store(newValue, forKey: toggleShortcutKey) }
    }

    static var finishShortcut: Shortcut {
        get { shortcut(forKey: finishShortcutKey) ?? .defaultFinish }
        set { store(newValue, forKey: finishShortcutKey) }
    }

    /// Absent means on: in screen mode the window would otherwise sit over the
    /// presentation being recorded.
    static var autoMinimizes: Bool {
        get { UserDefaults.standard.object(forKey: autoMinimizesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoMinimizesKey) }
    }

    /// Absent means on: in a tutorial, seeing where the click went is the point.
    static var showsMouseClicks: Bool {
        get { UserDefaults.standard.object(forKey: showsMouseClicksKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showsMouseClicksKey) }
    }

    static var launchMode: LaunchMode {
        get { UserDefaults.standard.string(forKey: launchModeKey).flatMap(LaunchMode.init) ?? .lastUsed }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: launchModeKey) }
    }

    /// Absent means on.
    static var checksForUpdatesAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: checksForUpdatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: checksForUpdatesKey) }
    }

    /// "Skip This Version": not offered again automatically, still found by hand.
    static var skippedUpdateVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedUpdateKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedUpdateKey) }
    }

    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedOnboardingKey) }
    }

    private static func shortcut(forKey key: String) -> Shortcut? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    private static func store(_ shortcut: Shortcut, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
}

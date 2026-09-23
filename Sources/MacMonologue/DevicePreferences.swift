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

    static var bubbleCorner: BubbleCorner {
        get { UserDefaults.standard.string(forKey: bubbleCornerKey).flatMap(BubbleCorner.init) ?? .bottomTrailing }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bubbleCornerKey) }
    }

    static var bubbleSize: BubbleSize {
        get { UserDefaults.standard.string(forKey: bubbleSizeKey).flatMap(BubbleSize.init) ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bubbleSizeKey) }
    }
}

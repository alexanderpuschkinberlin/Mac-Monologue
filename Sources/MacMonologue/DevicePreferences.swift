import Foundation

/// Remembers the camera and microphone across launches, by unique device ID.
///
/// IDs rather than names: a remembered device that has disappeared is shown as
/// unavailable instead of silently falling back to another camera, which is how
/// you record three minutes into the wrong lens.
enum DevicePreferences {
    private static let cameraKey = "selectedCameraID"
    private static let microphoneKey = "selectedMicrophoneID"

    static var cameraID: String? {
        get { UserDefaults.standard.string(forKey: cameraKey) }
        set { UserDefaults.standard.set(newValue, forKey: cameraKey) }
    }

    /// `DeviceOption.noAudioID` is a legitimate stored value — the user chose "No audio".
    static var microphoneID: String? {
        get { UserDefaults.standard.string(forKey: microphoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: microphoneKey) }
    }
}

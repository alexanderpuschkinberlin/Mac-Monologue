import Foundation

/// The two live meters, apart from `CaptureController` on purpose.
///
/// Meter readings change twenty times a second per source. Published on the
/// controller, every one of them re-evaluated everything that observes it - the
/// whole window, the Settings, the menu bar item (which macOS redraws for every
/// display) - and kept an idle app at 55-100 % CPU. Here only the meters observe
/// them. And a reading is only published when it moves enough to see: a quiet
/// microphone or a silent Mac costs nothing.
@MainActor
final class AudioLevels: ObservableObject {
    struct Reading: Equatable, Sendable {
        var level: Float
        var peak: Float
        var isClipping = false

        static let silent = Reading(level: AudioLevelMeter.floorDB, peak: AudioLevelMeter.floorDB)

        /// Below this the meter would not visibly move.
        static let visibleStepDB: Float = 0.5

        func isVisiblyDifferent(from other: Reading) -> Bool {
            abs(level - other.level) >= Self.visibleStepDB
                || abs(peak - other.peak) >= Self.visibleStepDB
                || isClipping != other.isClipping
        }
    }

    @Published private(set) var voice = Reading.silent
    @Published private(set) var system = Reading.silent

    func setVoice(_ reading: Reading) {
        if reading.isVisiblyDifferent(from: voice) { voice = reading }
    }

    func setSystem(_ reading: Reading) {
        if reading.isVisiblyDifferent(from: system) { system = reading }
    }
}

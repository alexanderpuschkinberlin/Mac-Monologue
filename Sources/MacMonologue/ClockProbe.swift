import CoreMedia
import Foundation

/// Checks that the screen recording's clock and the camera's clock can be related.
///
/// System audio arrives on ScreenCaptureKit's clock and is converted to the
/// capture session's with `CMSyncConvertTime`. That conversion is only meaningful
/// if the two clocks share an ancestor; if they do not, it silently returns
/// garbage and the audio drifts. This says which, instead of assuming.
enum ClockProbe {
    enum Verdict: Equatable {
        case agree
        case drifting
        case unrelated
    }

    struct Reading: Equatable {
        var relativeRate: Double
        var offsetSeconds: Double
        var verdict: Verdict
    }

    /// Pure, so it is tested with injected numbers rather than real clocks.
    static func verdict(relativeRate: Double, offsetSeconds: Double) -> Verdict {
        // CMSyncGetRelativeRate returns 0 when there is no common ancestor.
        guard relativeRate.isFinite, relativeRate > 0 else { return .unrelated }
        if abs(relativeRate - 1) > 1e-3 || abs(offsetSeconds) > 0.01 { return .drifting }
        return .agree
    }

    static func measure(from source: CMClock, to destination: CMClock) -> Reading {
        let rate = CMSyncGetRelativeRate(source, relativeTo: destination)
        let sourceNow = CMClockGetTime(source)
        let converted = CMSyncConvertTime(sourceNow, from: source, to: destination)
        let offset = (converted - CMClockGetTime(destination)).seconds
        return Reading(relativeRate: rate, offsetSeconds: offset,
                       verdict: verdict(relativeRate: rate, offsetSeconds: offset))
    }
}

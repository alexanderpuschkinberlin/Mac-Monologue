import CoreMedia

/// Maps capture time onto take time, with paused intervals removed.
///
/// This is the load-bearing piece of pause/resume and the only part of the app
/// that is unit-tested: a bug here produces a file that plays but is subtly
/// wrong, which is exactly the kind of thing you do not notice until later.
///
/// Deliberately free of AVFoundation — it takes timestamps and returns
/// timestamps, so it can be tested without a camera.
struct TakeClock: Equatable {
    /// Capture time at which the current running segment began.
    private var segmentStart: CMTime?
    /// Total take time accumulated by segments that have already ended.
    private var accumulated: CMTime = .zero

    var isRunning: Bool { segmentStart != nil }

    /// Take duration as of `now`. Frozen while paused.
    func elapsed(at now: CMTime) -> CMTime {
        guard let segmentStart else { return accumulated }
        return accumulated + (now - segmentStart)
    }

    /// Begin, or resume after a pause. A second call while running is ignored,
    /// so a stray Space keypress cannot corrupt the timeline.
    mutating func resume(at now: CMTime) {
        guard segmentStart == nil else { return }
        segmentStart = now
    }

    /// Pause. A call while already paused is ignored.
    mutating func pause(at now: CMTime) {
        guard let start = segmentStart else { return }
        accumulated = accumulated + (now - start)
        segmentStart = nil
    }

    /// Translate a capture timestamp into take time.
    ///
    /// Returns `nil` for samples that arrive while paused: the buffers keep
    /// coming from the capture session, and writing them would reinstate exactly
    /// the dead air pause is meant to remove.
    func takeTime(for captureTime: CMTime) -> CMTime? {
        guard let segmentStart else { return nil }
        guard captureTime >= segmentStart else {
            // A buffer captured before the resume point — in flight across the
            // pause boundary. Clamp it to the segment start rather than emitting
            // a timestamp that runs backwards.
            return accumulated
        }
        return accumulated + (captureTime - segmentStart)
    }
}

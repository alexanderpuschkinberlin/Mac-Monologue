import Foundation

/// Decides, frame by frame, whether the Touch Cut mode shows the screen or the
/// head. A finger on the trackpad cuts to the screen at once; lifting it cuts
/// back to the head only after `holdSeconds` — long enough that shifting a finger
/// or lifting it between swipes does not flicker between the two.
struct AutoCut {
    static let holdSeconds: CFTimeInterval = 0.7

    /// When a finger was last seen; nil before the first touch, so a take that
    /// starts with no finger down starts on the head.
    private var lastTouch: CFTimeInterval?

    mutating func showsScreen(touching: Bool, now: CFTimeInterval) -> Bool {
        if touching { lastTouch = now }
        guard let lastTouch else { return false }
        return now - lastTouch < Self.holdSeconds
    }
}

import Foundation
import os

/// Whether a finger rests on a trackpad — anywhere on the Mac, whatever app is in
/// front. The public APIs cannot say this: `NSTouch` only reaches a view under the
/// pointer in the key window, and a global `NSEvent` monitor only hears movement,
/// clicks and scrolling, never a finger lying still or being lifted.
///
/// So this reads Apple's private MultitouchSupport framework, the layer the
/// system's own gestures are built on. It is opened with `dlopen` rather than
/// linked: if a future macOS removes or renames it, the app still launches and
/// `isAvailable` is simply false. Only the finger *count* the callback is handed
/// is used — never the undocumented layout of the per-finger records — which keeps
/// what could break to the four function signatures below.
///
/// Start and stop on the main actor; `isTouching` is safe to read from any thread.
final class TrackpadTouch: @unchecked Sendable {
    private typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    private struct Symbols {
        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: Start
        let stop: Stop
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop")
        else { return nil }
        return Symbols(createList: unsafeBitCast(createList, to: CreateList.self),
                       register: unsafeBitCast(register, to: Register.self),
                       unregister: unsafeBitCast(unregister, to: Register.self),
                       start: unsafeBitCast(start, to: Start.self),
                       stop: unsafeBitCast(stop, to: Stop.self))
    }()

    /// Fingers down per device, keyed by the device's address: with a built-in and
    /// a Magic Trackpad, lifting off one must not hide a finger on the other.
    private static let fingers = OSAllocatedUnfairLock<[Int: Int32]>(initialState: [:])

    /// A C function pointer cannot capture, so the callback writes to static state.
    private static let callback: ContactCallback = { device, _, count, _, _ in
        guard let device else { return 0 }
        let key = Int(bitPattern: device)
        TrackpadTouch.fingers.withLock { $0[key] = count }
        return 0
    }

    /// Kept for as long as the devices run: the list owns them.
    private var devices: CFMutableArray?

    /// Whether this Mac has the framework the detection relies on.
    var isAvailable: Bool { Self.symbols != nil }

    /// At least one finger on at least one trackpad. False while stopped.
    var isTouching: Bool { Self.fingers.withLock { $0.values.contains { $0 > 0 } } }

    /// Starts listening, finding the trackpads afresh — one connected since the
    /// last start is picked up. Does nothing without the framework.
    func start() {
        stop()
        guard let symbols = Self.symbols,
              let list = symbols.createList()?.takeRetainedValue() else { return }
        devices = list
        for device in Self.pointers(in: list) {
            symbols.register(device, Self.callback)
            symbols.start(device, 0)
        }
    }

    func stop() {
        if let symbols = Self.symbols, let devices {
            for device in Self.pointers(in: devices) {
                symbols.unregister(device, Self.callback)
                symbols.stop(device)
            }
        }
        devices = nil
        Self.fingers.withLock { $0.removeAll() }
    }

    private static func pointers(in list: CFArray) -> [UnsafeMutableRawPointer] {
        (0..<CFArrayGetCount(list)).compactMap { UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, $0)) }
    }
}

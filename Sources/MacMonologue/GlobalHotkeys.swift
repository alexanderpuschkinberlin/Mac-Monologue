import AppKit
import Carbon.HIToolbox

/// A key combination that works from any app — while presenting, PowerPoint is
/// in front, and Space would turn the slide rather than pause the recording.
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, …), as `RegisterEventHotKey` wants them.
    var carbonModifiers: UInt32
    /// What the key itself is called, captured when the shortcut was recorded.
    var keyLabel: String

    static let defaultToggle = Shortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        keyLabel: "R"
    )
    static let defaultFinish = Shortcut(
        keyCode: UInt32(kVK_Return),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        keyLabel: "↩"
    )

    var hasControl: Bool { carbonModifiers & UInt32(controlKey) != 0 }
    var hasOption: Bool { carbonModifiers & UInt32(optionKey) != 0 }
    var hasShift: Bool { carbonModifiers & UInt32(shiftKey) != 0 }
    var hasCommand: Bool { carbonModifiers & UInt32(cmdKey) != 0 }

    /// Modifier symbols in the order macOS itself prints them.
    var modifierSymbols: [String] {
        var symbols: [String] = []
        if hasControl { symbols.append("⌃") }
        if hasOption { symbols.append("⌥") }
        if hasShift { symbols.append("⇧") }
        if hasCommand { symbols.append("⌘") }
        return symbols
    }

    var displayString: String { modifierSymbols.joined() + keyLabel }

    /// A global shortcut needs at least two modifiers, or it would fire while
    /// typing normally in other apps.
    var isAcceptable: Bool { modifierSymbols.count >= 2 }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// From a key press, as recorded in Settings.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        let label: String
        switch Int(event.keyCode) {
        case kVK_Return: label = "↩"
        case kVK_Space: label = "Space"
        case kVK_Tab: label = "⇥"
        case kVK_Delete: label = "⌫"
        case kVK_Escape: return nil
        default:
            guard let characters = event.charactersIgnoringModifiers?.uppercased(),
                  !characters.isEmpty else { return nil }
            label = characters
        }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, keyLabel: label)
    }
}

/// Registers the global shortcuts with Carbon's `RegisterEventHotKey`.
///
/// Deliberately not a global `NSEvent` monitor: that would need the Input
/// Monitoring permission — a fourth permission to explain — while a registered
/// hot key needs none.
@MainActor
final class GlobalHotkeys {
    enum Action: UInt32, CaseIterable {
        case toggleRecording = 1
        case finish = 2
    }

    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((Action) -> Void)?

    /// Which shortcuts could not be registered — usually because another app
    /// already owns that combination.
    private(set) var failed: [Action] = []

    func register(_ bindings: [Action: Shortcut]) {
        unregisterAll()
        installHandlerIfNeeded()

        failed = []
        for (action, shortcut) in bindings {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, identifier,
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registrations.append(reference)
            } else {
                failed.append(action)
            }
        }
    }

    func unregisterAll() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
    }

    /// 'MMLG'
    private static let signature: OSType = 0x4D4D_4C47

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == GlobalHotkeys.signature,
                  let action = Action(rawValue: identifier.id) else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot keys on the main run loop.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            }
            return noErr
        }, 1, &eventType, context, &handler)
    }
}

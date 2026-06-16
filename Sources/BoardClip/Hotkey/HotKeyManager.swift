import AppKit
import Carbon.HIToolbox

/// Stored outside the actor so the C event handler (a non-capturing function pointer) can reach it.
nonisolated(unsafe) private var hotKeyActivationHandler: (() -> Void)?

/// Registers a single global hotkey via the Carbon Event Manager — the reliable, system-wide
/// mechanism still supported on current macOS (and used by most menu-bar utilities).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    var onActivate: (() -> Void)? {
        didSet { hotKeyActivationHandler = onActivate }
    }

    private init() {}

    /// (Re)register the hotkey. `keyCode` is a virtual key code; `flags` are Cocoa modifier flags.
    func register(keyCode: Int, flags: NSEvent.ModifierFlags) {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharCode("BCLP"), id: 1)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: flags),
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ in
                // Carbon delivers hotkey events on the main thread. Call synchronously (don't defer
                // with async) so AppKit still treats activation as user-initiated and honors it.
                MainActor.assumeIsolated { hotKeyActivationHandler?() }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}

/// Map Cocoa modifier flags to Carbon modifier masks.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.option)  { m |= UInt32(optionKey) }
    if flags.contains(.shift)   { m |= UInt32(shiftKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    return m
}

private func fourCharCode(_ s: String) -> FourCharCode {
    var code: FourCharCode = 0
    for ch in s.utf8.prefix(4) { code = (code << 8) + FourCharCode(ch) }
    return code
}

import AppKit
import Carbon.HIToolbox

enum QuickPasteShortcut {
    static let slotCount = 9
    static let firstHotKeyID: UInt32 = 101
    static let keyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
        kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
        kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    static func hotKeyID(for slot: Int) -> UInt32? {
        guard (0..<slotCount).contains(slot) else { return nil }
        return firstHotKeyID + UInt32(slot)
    }

    static func slot(forHotKeyID id: UInt32) -> Int? {
        guard id >= firstHotKeyID else { return nil }
        let slot = Int(id - firstHotKeyID)
        return (0..<slotCount).contains(slot) ? slot : nil
    }

    static func item(at slot: Int, in items: [ClipItem]) -> ClipItem? {
        items.indices.contains(slot) ? items[slot] : nil
    }
}

/// Registers global hotkeys via the Carbon Event Manager — the reliable, system-wide
/// mechanism still supported on current macOS (and used by most menu-bar utilities).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private static let openHUDHotKeyID: UInt32 = 1

    private var openHUDHotKeyRef: EventHotKeyRef?
    private var quickPasteHotKeyRefs: [Int: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    var onActivate: (() -> Void)?
    var onQuickPaste: ((Int) -> Void)?

    private init() {}

    /// (Re)register the hotkey. `keyCode` is a virtual key code; `flags` are Cocoa modifier flags.
    @discardableResult
    func register(keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharCode("BCLP"), id: Self.openHUDHotKeyID)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: flags),
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            openHUDHotKeyRef = ref
            return true
        }
        NSLog("[BoardClip] Could not register global shortcut (status \(status))")
        return false
    }

    func unregister() {
        if let ref = openHUDHotKeyRef {
            UnregisterEventHotKey(ref)
            openHUDHotKeyRef = nil
        }
    }

    /// Register Command-Option-1 through 9. Returns the one-based slots another app already owns.
    @discardableResult
    func registerQuickPasteShortcuts() -> [Int] {
        unregisterQuickPasteShortcuts()
        installHandlerIfNeeded()

        var unavailableSlots: [Int] = []
        let modifiers = carbonModifiers(from: [.command, .option])
        for (slot, keyCode) in QuickPasteShortcut.keyCodes.enumerated() {
            guard let hotKeyID = QuickPasteShortcut.hotKeyID(for: slot) else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode),
                modifiers,
                EventHotKeyID(signature: fourCharCode("BCLP"), id: hotKeyID),
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                quickPasteHotKeyRefs[slot] = ref
            } else {
                unavailableSlots.append(slot + 1)
                NSLog("[BoardClip] Could not register direct paste shortcut %d (status %d)", slot + 1, status)
            }
        }
        return unavailableSlots
    }

    func unregisterQuickPasteShortcuts() {
        for ref in quickPasteHotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        quickPasteHotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                // Carbon delivers hotkey events on the main thread. Call synchronously (don't defer
                // with async) so AppKit still treats activation as user-initiated and honors it.
                MainActor.assumeIsolated {
                    HotKeyManager.shared.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }

    private func handleHotKey(id: UInt32) {
        if id == Self.openHUDHotKeyID {
            onActivate?()
        } else if let slot = QuickPasteShortcut.slot(forHotKeyID: id) {
            onQuickPaste?(slot)
        }
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

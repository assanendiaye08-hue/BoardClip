import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Human-readable rendering of a key code + modifier flags (e.g. "⌘⌥V").
enum KeyDisplay {
    static func string(keyCode: Int, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String {
        if let special = special[code] { return special }
        if let s = letters[code] { return s }
        return "Key \(code)"
    }

    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    private static let letters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]
}

/// Click to record; the next key combo (with at least one modifier) becomes the global hotkey.
struct ShortcutRecorder: View {
    @Bindable var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var registrationError: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut… (⎋ to cancel)"
                               : KeyDisplay.string(keyCode: settings.hotKeyCode, flags: settings.modifierFlags))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 150)
            }
            .buttonStyle(.glass)
            if let registrationError {
                Text(registrationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape { stop(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil } // require at least one modifier
            let previousCode = settings.hotKeyCode
            let previousModifiers = settings.hotKeyModifiers
            settings.hotKeyCode = Int(event.keyCode)
            settings.hotKeyModifiers = mods.rawValue
            if AppDelegate.shared?.reloadHotKey() == false {
                settings.hotKeyCode = previousCode
                settings.hotKeyModifiers = previousModifiers
                AppDelegate.shared?.reloadHotKey()
                registrationError = "That shortcut is already in use."
            } else {
                registrationError = nil
            }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

import SwiftUI
import AppKit

/// First-run window: explains the hotkey and walks through the one permission BoardClip needs.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: OnboardingView { close() })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }
}

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var axGranted = Permissions.accessibilityGranted
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                Text("Welcome to \(AppInfo.name)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Your clipboard, on glass.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 16) {
                row(icon: "command", title: "Summon it anywhere",
                    detail: "Press \(KeyDisplay.string(keyCode: Settings.shared.hotKeyCode, flags: Settings.shared.modifierFlags)) to open the clipboard bar. Click a clip — or press ⌘1–9 — to paste.")

                permissionRow

                Toggle(isOn: $launchAtLogin) {
                    Label("Launch at login", systemImage: "power")
                        .font(.system(size: 14, weight: .medium))
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onDone) {
                Text("Start Using \(AppInfo.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 580)
        .onReceive(tick) { _ in axGranted = Permissions.accessibilityGranted }
    }

    private var permissionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: axGranted ? "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(axGranted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste into any app")
                    .font(.system(size: 14, weight: .medium))
                Text(axGranted
                     ? "Accessibility is enabled — clips paste straight into the focused field."
                     : "Grant Accessibility so BoardClip can paste for you. Without it, clips are still copied — just press ⌘V yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !axGranted {
                    Button("Open Accessibility Settings") {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

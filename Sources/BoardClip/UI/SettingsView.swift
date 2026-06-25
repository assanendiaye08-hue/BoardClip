import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcut", systemImage: "command") }
            HistorySettings()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SpacesSettings()
                .tabItem { Label("Spaces", systemImage: "tray.full") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 430)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings = Settings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch BoardClip at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v) }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Text("When hidden, open BoardClip with your shortcut, then click the gear or press ⌘, for Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Capture ⌘⇧4 screenshots automatically", isOn: $settings.watchScreenshots)
                    .onChange(of: settings.watchScreenshots) { _, v in AppDelegate.shared?.setScreenshotWatching(v) }
            }
            Section("Pasting") {
                Toggle("Paste as plain text by default", isOn: $settings.pasteAsPlainDefault)
                Text("Hold ⌥ while choosing a clip to invert this.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Clip Bar") {
                VStack(alignment: .leading) {
                    Text("Mouse scroll speed \(Int(settings.clipScrollSensitivity * 100))%")
                    Slider(value: $settings.clipScrollSensitivity, in: 0.10...1.00, step: 0.05) {
                        Text("Mouse scroll speed")
                    } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Fast") }
                }
            }
            Section {
                Toggle("Play a sound when capturing", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut

private struct ShortcutSettings: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack {
                    Text("Open BoardClip")
                    Spacer()
                    ShortcutRecorder()
                }
                Text("Press the shortcut anywhere to open the clipboard bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Monitoring") {
                VStack(alignment: .leading) {
                    Text("Check the clipboard every \(settings.pollInterval, specifier: "%.1f")s")
                    Slider(value: $settings.pollInterval, in: 0.2...1.5, step: 0.1) {
                        Text("Poll interval")
                    } minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Light") }
                        .onChange(of: settings.pollInterval) { _, _ in AppDelegate.shared?.restartMonitor() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

private struct HistorySettings: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section("Retention") {
                Stepper("Keep up to \(settings.maxItems) clips", value: $settings.maxItems, in: 50...10_000, step: 50)
                Stepper(retentionLabel, value: $settings.retentionDays, in: 0...365, step: 1)
                Text("Pinned clips and clips saved to a Space are never removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Clear History Now", role: .destructive) {
                    AppDelegate.shared?.store.clearAll()
                }
                Text("Keeps pinned and Space-saved clips.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var retentionLabel: String {
        settings.retentionDays == 0
            ? "Keep clips forever"
            : "Delete clips older than \(settings.retentionDays) day\(settings.retentionDays == 1 ? "" : "s")"
    }
}

// MARK: - Spaces

private struct SpacesSettings: View {
    @State private var newName = ""
    @State private var newSymbol = "tray.full"
    @State private var newColor = "#0A84FF"

    private let symbols = ["tray.full", "star", "bookmark", "folder", "lightbulb", "hammer", "cart", "heart", "tag", "doc.text"]
    private let colors = ["#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#64D2FF"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let spaceStore = AppDelegate.shared?.spaceStore,
               let store = AppDelegate.shared?.store {
                List {
                    ForEach(spaceStore.spaces) { space in
                        SpaceRow(space: space, spaceStore: spaceStore, store: store)
                    }
                    if spaceStore.spaces.isEmpty {
                        Text("No Spaces yet. Create one below, then right-click a clip → Add to Space.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Menu { ForEach(symbols, id: \.self) { s in Button { newSymbol = s } label: { Label(s, systemImage: s) } } }
                        label: { Image(systemName: newSymbol).frame(width: 22) }
                        .menuStyle(.borderlessButton).fixedSize()
                    Menu { ForEach(colors, id: \.self) { c in Button { newColor = c } label: { Text(c) } } }
                        label: { Circle().fill(Color(nsColor: NSColor(hex: newColor) ?? .systemBlue)).frame(width: 16, height: 16) }
                        .menuStyle(.borderlessButton).fixedSize()
                    TextField("New Space name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add).buttonStyle(.glass).disabled(newName.trimmed.isEmpty)
                }
                .padding(12)
            } else {
                Text("Loading…").foregroundStyle(.secondary).padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func add() {
        guard let spaceStore = AppDelegate.shared?.spaceStore else { return }
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        spaceStore.add(name: name, symbol: newSymbol, colorHex: newColor)
        newName = ""
    }
}

private struct SpaceRow: View {
    let space: Space
    let spaceStore: SpaceStore
    let store: HistoryStore
    @State private var name: String

    init(space: Space, spaceStore: SpaceStore, store: HistoryStore) {
        self.space = space; self.spaceStore = spaceStore; self.store = store
        _name = State(initialValue: space.name)
    }

    var body: some View {
        HStack {
            Image(systemName: space.symbol)
                .foregroundStyle(Color(nsColor: NSColor(hex: space.colorHex) ?? .systemBlue))
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { spaceStore.rename(space, to: name.trimmed.isEmpty ? space.name : name.trimmed) }
            Spacer()
            Button(role: .destructive) {
                spaceStore.delete(space, from: store)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Ignore passwords & secret clips", isOn: $settings.ignoreConcealed)
                Text("Honors the standard concealed/transient markers password managers use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded Apps") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("Clips from these apps will never be captured.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(appName(for: id))
                        Spacer()
                        Button(role: .destructive) {
                            settings.excludedBundleIDs.removeAll { $0 == id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addApp).buttonStyle(.glass)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return id
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !settings.excludedBundleIDs.contains(id) { settings.excludedBundleIDs.append(id) }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 52)).foregroundStyle(.tint)
            Text(AppInfo.name).font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Check for Updates…") { AppDelegate.shared?.checkForUpdates() }
                    .buttonStyle(.glass)
                Button("GitHub") { NSWorkspace.shared.open(AppInfo.githubURL) }
                    .buttonStyle(.glass)
            }
            .padding(.top, 4)
            Spacer()
            Text("A clipboard manager, on glass.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

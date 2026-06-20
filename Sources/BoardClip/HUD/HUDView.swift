import SwiftUI

/// The Pasty-style horizontal glass strip: search + Space filter on top, recency-ordered cards below.
struct HUDView: View {
    let store: HistoryStore
    let spaceStore: SpaceStore
    let settings: Settings
    let session: HUDSession

    var onPaste: (ClipItem, Bool) -> Void
    var onClose: () -> Void
    var onAddSpace: () -> Void
    var onTogglePin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void
    var onToggleSpace: (UUID, ClipItem) -> Void
    var onSaveToPhotos: (ClipItem) -> Void
    var onResearch: (ClipItem) -> Void
    var onReveal: (ClipItem) -> Void
    var onTransformPaste: (ClipItem, ItemActions.Transform) -> Void

    @State private var search = ""
    @State private var selected = 0
    @State private var selectedSpace: UUID?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var spaceFiltered: [ClipItem] {
        guard let sid = selectedSpace else { return store.items }
        return store.items.filter { $0.spaceIDs.contains(sid) }
    }

    private var filtered: [ClipItem] {
        let base = spaceFiltered
        guard !search.isEmpty else { return base }
        return base
            .compactMap { item -> (ClipItem, Int)? in
                let hay = "\(item.preview) \(item.sourceAppName ?? "") \(item.kind.label)"
                return Fuzzy.score(search, in: hay).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let visible = filtered   // compute the fuzzy filter once per render, not 4×
        return GlassEffectContainer {
            VStack(spacing: 12) {
                header(count: visible.count)
                spacePills
                if visible.isEmpty { emptyState } else { strip(visible) }
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Pinned to the top edge: square top corners, rounded bottom.
            .glassEffect(.regular, in: UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: Design.barCornerRadius,
                bottomTrailingRadius: Design.barCornerRadius, topTrailingRadius: 0, style: .continuous))
        }
        .background(quickPasteButtons)
        .onExitCommand(perform: onClose)
        .onAppear {
            resetForOpen()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: session.openCount) { _, _ in resetForOpen() }
        .onChange(of: search) { selected = 0 }
        .onChange(of: selectedSpace) { selected = 0 }
        .onChange(of: visible.count) { _, n in selected = min(selected, max(0, n - 1)) }
    }

    private func resetForOpen() {
        search = ""
        selectedSpace = nil
        selected = 0
        searchFocused = true
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clips…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { pasteSelected() }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(width: 300)
            .background(.white.opacity(0.08), in: Capsule())

            Spacer()
            Text(AppInfo.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()

            Text("\(count) clip\(count == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var spacePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(title: "Recent", systemImage: "clock", id: nil)
                ForEach(spaceStore.spaces) { space in
                    pill(title: space.name, systemImage: space.symbol, id: space.id)
                }
                Button(action: onAddSpace) {
                    Label("New Space", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 30)
    }

    private func pill(title: String, systemImage: String, id: UUID?) -> some View {
        let active = selectedSpace == id
        return Button {
            selectedSpace = id
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
        .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
    }

    // MARK: Strip

    private func strip(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy: only the visible cards (and their image decodes) are built, so opening the bar
                // is O(visible) instead of O(history) — fast even with hundreds of clips.
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button { pasteItem(item) } label: {
                            ClipCardView(item: item, index: idx, selected: idx == selected)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .onHover { hovering in if hovering { selected = idx } }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(height: Design.cardHeight + 8)
            .onChange(of: selected) { _, _ in scrollSelected(in: items, proxy: proxy) }
            .onChange(of: items.map(\.id)) { _, _ in scrollSelected(in: items, proxy: proxy, animated: false) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Design.cardHeight + 8)
    }

    private var emptyMessage: String {
        if !search.isEmpty { return "No matching clips" }
        if selectedSpace != nil { return "This Space is empty — right-click a clip to add it" }
        return "Nothing copied yet"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("⌘1–9", "Paste")
            hint("↩", "Paste selected")
            hint("←/→", "Select")
            hint("⌥", "Paste as text")
            Spacer()
            hint("esc", "Close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }

    // MARK: Hidden ⌘1–9 shortcuts

    private var quickPasteButtons: some View {
        ForEach(0..<9, id: \.self) { i in
            Button("") { if i < filtered.count { pasteItem(filtered[i]) } }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .opacity(0)
        }
    }

    // MARK: Context menu

    @ViewBuilder private func contextMenu(for item: ClipItem) -> some View {
        Button("Paste") { onPaste(item, false) }
        Button("Paste as Plain Text") { onPaste(item, true) }
        if item.kind == .text || item.kind == .rtf || item.kind == .link {
            Menu("Transform & Paste") {
                ForEach(ItemActions.Transform.allCases) { t in
                    Button(t.rawValue) { onTransformPaste(item, t) }
                }
            }
        }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { onTogglePin(item) }
        if !spaceStore.spaces.isEmpty {
            Menu("Add to Space") {
                ForEach(spaceStore.spaces) { space in
                    Button {
                        onToggleSpace(space.id, item)
                    } label: {
                        Label(space.name, systemImage: item.spaceIDs.contains(space.id) ? "checkmark" : space.symbol)
                    }
                }
            }
        }
        if item.kind == .image { Button("Save to Photos") { onSaveToPhotos(item) } }
        if item.kind == .file { Button("Reveal in Finder") { onReveal(item) } }
        if !item.bestPlainText.isEmpty { Button("Research") { onResearch(item) } }
        Divider()
        Button("Delete", role: .destructive) { onDelete(item) }
    }

    // MARK: Actions

    private func pasteSelected() {
        guard !filtered.isEmpty else { return }
        pasteItem(filtered[min(selected, filtered.count - 1)])
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        selected = min(max(selected + delta, 0), filtered.count - 1)
    }

    private func scrollSelected(in items: [ClipItem], proxy: ScrollViewProxy, animated: Bool = true) {
        guard items.indices.contains(selected) else { return }
        let action = { proxy.scrollTo(items[selected].id, anchor: .center) }
        if animated {
            withAnimation(.easeOut(duration: 0.12), action)
        } else {
            action()
        }
    }

    private func pasteItem(_ item: ClipItem) {
        let plain = settings.pasteAsPlainDefault != NSEvent.modifierFlags.contains(.option)
        onPaste(item, plain)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window is HUDPanel || NSApp.keyWindow is HUDPanel else { return event }
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return event }

        switch event.keyCode {
        case HUDKeyCode.leftArrow, HUDKeyCode.upArrow:
            moveSelection(by: -1)
            return nil
        case HUDKeyCode.rightArrow, HUDKeyCode.downArrow:
            moveSelection(by: 1)
            return nil
        default:
            return event
        }
    }
}

private enum HUDKeyCode {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

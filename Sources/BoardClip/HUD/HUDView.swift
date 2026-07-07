import SwiftUI

/// The Pasty-style horizontal glass strip: search + Space filter on top, recency-ordered cards below.
struct HUDView: View {
    let store: HistoryStore
    let spaceStore: SpaceStore
    let settings: Settings
    let session: HUDSession

    var onPaste: (ClipItem, Bool) -> Void
    var onPasteCombined: ([ClipItem]) -> Void
    var onClose: () -> Void
    var onAddSpace: () -> Void
    var onTogglePin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void
    var onToggleSpace: (UUID, ClipItem) -> Void
    var onEditSpaceNote: (ClipItem, UUID) -> Void
    var onEditText: (ClipItem) -> Void
    var onSaveToPhotos: (ClipItem) -> Void
    var onResearch: (ClipItem) -> Void
    var onReveal: (ClipItem) -> Void
    var onTransformPaste: (ClipItem, ItemActions.Transform) -> Void
    var onSettings: () -> Void

    @State private var search = ""
    @State private var selected = 0
    @State private var multiSelectedIDs: [UUID] = []
    @State private var selectedSpace: UUID?
    @State private var shouldCenterSelectedClip = false
    @State private var suppressHoverSelection = false
    @State private var hoverUnlockMouseLocation: NSPoint?
    @State private var hoveredIndex: Int?
    @State private var keyMonitor: Any?
    @State private var pointerMonitor: Any?
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
                let hay = "\(item.preview) \(item.note(in: selectedSpace) ?? "") \(item.sourceAppName ?? "") \(item.kind.label)"
                return Fuzzy.score(search, in: hay).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let visible = filtered   // compute the fuzzy filter once per render, not 4×
        let multiItems = multiSelectedItems()
        return GlassEffectContainer {
            VStack(spacing: 12) {
                header(count: visible.count)
                spacePills
                if visible.isEmpty { emptyState } else { strip(visible) }
                footer(selectedCount: multiItems.count)
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
            installEventMonitors()
        }
        .onDisappear { removeEventMonitors() }
        .onChange(of: session.openCount) { _, _ in resetForOpen() }
        .onChange(of: search) {
            allowHoverSelection()
            shouldCenterSelectedClip = false
            selected = 0
        }
        .onChange(of: selectedSpace) {
            allowHoverSelection()
            shouldCenterSelectedClip = false
            selected = 0
        }
        .onChange(of: visible.count) { _, n in
            allowHoverSelection()
            shouldCenterSelectedClip = false
            selected = min(selected, max(0, n - 1))
        }
        .onChange(of: store.items.map(\.id)) { _, _ in pruneMultiSelection() }
    }

    private func resetForOpen() {
        search = ""
        selectedSpace = nil
        selected = 0
        multiSelectedIDs.removeAll()
        shouldCenterSelectedClip = false
        allowHoverSelection()
        hoveredIndex = nil
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

            HStack(spacing: 10) {
                Text("\(count) clip\(count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: Circle())
                .foregroundStyle(.secondary)
                .help("Settings")
            }
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
                        Button { handleClipClick(item) } label: {
                            ClipCardView(
                                item: item,
                                index: idx,
                                selected: idx == selected,
                                multiSelected: isMultiSelected(item),
                                spaceNote: item.note(in: selectedSpace)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .onHover { hovering in
                            if hovering {
                                hoveredIndex = idx
                                selectHoveredClip(idx)
                            } else if hoveredIndex == idx {
                                hoveredIndex = nil
                            }
                        }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(height: Design.cardHeight + 8)
            .background(ClipScrollSensitivityTuner(sensitivity: settings.clipScrollSensitivity))
            .onChange(of: selected) { _, _ in
                guard shouldCenterSelectedClip else { return }
                shouldCenterSelectedClip = false
                scrollSelected(in: items, proxy: proxy)
            }
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

    private func footer(selectedCount: Int) -> some View {
        HStack(spacing: 12) {
            if selectedCount > 0 {
                Button {
                    pasteMultiSelected()
                } label: {
                    Label("Paste \(selectedCount)", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .background(.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(.white)
                .help("Paste marked clips together")

                Button {
                    multiSelectedIDs.removeAll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: Circle())
                .foregroundStyle(.secondary)
                .help("Clear marked clips")
            }

            hint("⌘1–9", "Paste")
            hint("↩", selectedCount > 0 ? "Paste marked" : "Paste selected")
            hint("space", "Mark")
            hint("←/→", "Select")
            hint("⌥", "Paste as text")
            hint("⌘,", "Settings")
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
        Group {
            ForEach(0..<9, id: \.self) { i in
                Button("") { if i < filtered.count { pasteItem(filtered[i]) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .opacity(0)
            }
            Button("") { onSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
        }
    }

    // MARK: Context menu

    @ViewBuilder private func contextMenu(for item: ClipItem) -> some View {
        Button("Paste") { onPaste(item, false) }
        Button("Paste as Plain Text") { onPaste(item, true) }
        if canMultiPaste(item) {
            Button(isMultiSelected(item) ? "Remove from Multi-Paste" : "Select for Multi-Paste") {
                toggleMultiSelection(item)
            }
        }
        if !multiSelectedItems().isEmpty {
            Button("Paste Selected Clips") { pasteMultiSelected() }
            Button("Clear Multi-Paste Selection") { multiSelectedIDs.removeAll() }
        }
        if item.isTextEditable {
            Button("Edit Text…") { onEditText(item) }
        }
        if item.kind == .text || item.kind == .rtf || item.kind == .link {
            Menu("Transform & Paste") {
                ForEach(ItemActions.Transform.allCases) { t in
                    Button(t.rawValue) { onTransformPaste(item, t) }
                }
            }
        }
        Divider()
        if let selectedSpace {
            Button(item.note(in: selectedSpace) == nil ? "Add Note" : "Edit Note") {
                onEditSpaceNote(item, selectedSpace)
            }
        }
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
        let marked = multiSelectedItems()
        if !marked.isEmpty {
            pasteMultiSelected(marked)
            return
        }

        guard !filtered.isEmpty else { return }
        pasteItem(filtered[min(selected, filtered.count - 1)])
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let next = min(max(selected + delta, 0), filtered.count - 1)
        guard next != selected else { return }
        suppressHoverSelectionUntilMouseMoves()
        shouldCenterSelectedClip = true
        selected = next
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
        multiSelectedIDs.removeAll()
        let plain = settings.pasteAsPlainDefault != NSEvent.modifierFlags.contains(.option)
        onPaste(item, plain)
    }

    private func handleClipClick(_ item: ClipItem) {
        let toggleModifiers: NSEvent.ModifierFlags = [.command, .shift]
        if !NSEvent.modifierFlags.intersection(toggleModifiers).isEmpty {
            toggleMultiSelection(item)
        } else {
            pasteItem(item)
        }
    }

    private func pasteMultiSelected() {
        pasteMultiSelected(multiSelectedItems())
    }

    private func pasteMultiSelected(_ items: [ClipItem]) {
        let usableItems = items.filter(canMultiPaste)
        guard !usableItems.isEmpty else {
            multiSelectedIDs.removeAll()
            return
        }
        multiSelectedIDs.removeAll()
        onPasteCombined(usableItems)
    }

    private func toggleCurrentMultiSelection() {
        guard filtered.indices.contains(selected) else { return }
        toggleMultiSelection(filtered[selected])
    }

    private func toggleMultiSelection(_ item: ClipItem) {
        guard canMultiPaste(item) else { return }

        if let index = multiSelectedIDs.firstIndex(of: item.id) {
            multiSelectedIDs.remove(at: index)
        } else {
            multiSelectedIDs.append(item.id)
        }
    }

    private func isMultiSelected(_ item: ClipItem) -> Bool {
        multiSelectedIDs.contains(item.id)
    }

    private func multiSelectedItems() -> [ClipItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
        var seen = Set<UUID>()
        return multiSelectedIDs.compactMap { id in
            guard !seen.contains(id), let item = itemsByID[id], canMultiPaste(item) else { return nil }
            seen.insert(id)
            return item
        }
    }

    private func pruneMultiSelection() {
        let availableIDs = Set(store.items.map(\.id))
        multiSelectedIDs.removeAll { !availableIDs.contains($0) }
    }

    private func canMultiPaste(_ item: ClipItem) -> Bool {
        !item.bestPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func selectHoveredClip(_ index: Int) {
        guard !suppressHoverSelection else { return }
        shouldCenterSelectedClip = false
        selected = index
    }

    private func suppressHoverSelectionUntilMouseMoves() {
        suppressHoverSelection = true
        hoverUnlockMouseLocation = NSEvent.mouseLocation
    }

    private func allowHoverSelection() {
        suppressHoverSelection = false
        hoverUnlockMouseLocation = nil
    }

    private func installEventMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { event in
            handlePointerMove(event)
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window is HUDPanel || NSApp.keyWindow is HUDPanel else { return event }
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return event }
        let shiftPressed = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case HUDKeyCode.leftArrow, HUDKeyCode.upArrow:
            guard !shiftPressed else { return event }
            moveSelection(by: -1)
            return nil
        case HUDKeyCode.rightArrow, HUDKeyCode.downArrow:
            guard !shiftPressed else { return event }
            moveSelection(by: 1)
            return nil
        case HUDKeyCode.space where shiftPressed || search.isEmpty:
            toggleCurrentMultiSelection()
            return nil
        case HUDKeyCode.returnKey, HUDKeyCode.keypadEnter:
            pasteSelected()
            return nil
        default:
            return event
        }
    }

    private func handlePointerMove(_ event: NSEvent) -> NSEvent? {
        guard suppressHoverSelection else { return event }

        guard let start = hoverUnlockMouseLocation else {
            allowHoverSelection()
            return event
        }

        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard dx * dx + dy * dy >= 9 else { return event }

        allowHoverSelection()
        if let hoveredIndex, filtered.indices.contains(hoveredIndex) {
            selectHoveredClip(hoveredIndex)
        }
        return event
    }
}

private enum HUDKeyCode {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let space: UInt16 = 49
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
}

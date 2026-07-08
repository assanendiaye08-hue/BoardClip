import AppKit
import Observation

/// The clipboard history: an in-memory, recency-ordered list backed by an atomic JSON file.
/// Newest item is always at index 0. Image bytes are stored as external blobs.
@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [ClipItem] = []

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "com.boardclip.history.io")
    @ObservationIgnored private var imageTextRecognitionTask: Task<Void, Never>?
    @ObservationIgnored private var pendingImageTextRecognitionIDs = Set<UUID>()

    init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Loading / saving

    func load() {
        AppPaths.ensure()
        guard let data = try? Data(contentsOf: AppPaths.historyFile) else { return }
        if let decoded = try? JSONDecoder.iso.decode([ClipItem].self, from: data) {
            items = decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
            queueImageTextRecognitionBackfill()
        }
    }

    /// Debounced save. All writes funnel through `ioQueue` (serial) so a debounced save can never
    /// clobber a later `flush()`.
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.write(self.items)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func write(_ snapshot: [ClipItem]) {
        ioQueue.async {
            guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }
            try? data.write(to: AppPaths.historyFile, options: .atomic)
        }
    }

    /// Force an immediate save (e.g. on quit). Runs after any in-flight debounced write, so the
    /// newest data wins.
    func flush() {
        saveWork?.cancel()
        let snapshot = items
        ioQueue.sync {
            guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }
            try? data.write(to: AppPaths.historyFile, options: .atomic)
        }
    }

    // MARK: Ingest

    @discardableResult
    func ingest(_ draft: PasteboardDraft) -> ClipItem {
        // De-dupe: a re-copy promotes the existing item instead of adding a duplicate.
        if let idx = items.firstIndex(where: { $0.contentHash == draft.contentHash }) {
            var existing = items.remove(at: idx)
            existing.lastUsedAt = Date()
            items.insert(existing, at: 0)
            queueImageTextRecognitionIfNeeded(for: existing)
            scheduleSave()
            return existing
        }

        var imageFileName: String?
        if let png = draft.imagePNG {
            let name = "\(UUID().uuidString).png"
            try? png.write(to: AppPaths.blobURL(name), options: .atomic)
            imageFileName = name
        }

        let now = Date()
        let item = ClipItem(
            kind: draft.kind, createdAt: now, lastUsedAt: now,
            sourceBundleID: draft.sourceBundleID, sourceAppName: draft.sourceAppName,
            contentHash: draft.contentHash,
            text: draft.text, rtfData: draft.rtfData,
            imageFileName: imageFileName, imageWidth: draft.imageWidth, imageHeight: draft.imageHeight,
            fileURLs: draft.fileURLs, urlString: draft.urlString, colorHex: draft.colorHex,
            byteSize: byteSize(of: draft)
        )
        items.insert(item, at: 0)
        enforceCap()
        queueImageTextRecognitionIfNeeded(for: item)
        scheduleSave()
        return item
    }

    @discardableResult
    func ingestText(_ text: String, sourceAppName: String = AppInfo.name) -> ClipItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let draft = PasteboardDraft(
            kind: .text,
            text: text,
            rtfData: nil,
            imagePNG: nil,
            imageWidth: nil,
            imageHeight: nil,
            fileURLs: nil,
            urlString: nil,
            colorHex: nil,
            sourceBundleID: AppInfo.bundleID,
            sourceAppName: sourceAppName,
            hash: Data(text.utf8)
        )
        return ingest(draft)
    }

    /// Add a pre-built item (used by the screenshot watcher).
    func add(_ item: ClipItem) {
        if items.contains(where: { $0.contentHash == item.contentHash }) { return }
        items.insert(item, at: 0)
        enforceCap()
        queueImageTextRecognitionIfNeeded(for: item)
        scheduleSave()
    }

    // MARK: Mutations

    func markUsed(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var it = items.remove(at: idx)
        it.lastUsedAt = Date()
        items.insert(it, at: 0)
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: idx)
        deleteBlob(removed)
        scheduleSave()
    }

    func clearAll(keepProtected: Bool = true) {
        let survivors = keepProtected ? items.filter(\.isProtected) : []
        for item in items where !survivors.contains(where: { $0.id == item.id }) {
            deleteBlob(item)
        }
        items = survivors
        scheduleSave()
    }

    func setSpaces(_ ids: [UUID], for item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].spaceIDs = ids
        pruneSpaceNotes(at: idx)
        scheduleSave()
    }

    /// Add/remove an item to/from a Space.
    func toggleSpace(_ spaceID: UUID, for item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if let pos = items[idx].spaceIDs.firstIndex(of: spaceID) {
            items[idx].spaceIDs.remove(at: pos)
        } else {
            items[idx].spaceIDs.append(spaceID)
        }
        pruneSpaceNotes(at: idx)
        scheduleSave()
    }

    func setSpaceNote(_ note: String?, for item: ClipItem, in spaceID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let key = spaceID.uuidString
        var notes = items[idx].spaceNotes ?? [:]
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty {
            notes.removeValue(forKey: key)
        } else {
            notes[key] = trimmed
        }
        items[idx].spaceNotes = notes.isEmpty ? nil : notes
        scheduleSave()
    }

    func updateText(_ text: String, for item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              items[idx].isTextEditable else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isLink(trimmed) {
            items[idx].kind = .link
            items[idx].text = trimmed
            items[idx].urlString = trimmed
            items[idx].contentHash = ClipContentHash.make(kind: .link, seed: Data(trimmed.utf8))
            items[idx].byteSize = trimmed.utf8.count
        } else {
            items[idx].kind = .text
            items[idx].text = text
            items[idx].urlString = nil
            items[idx].contentHash = ClipContentHash.make(kind: .text, seed: Data(text.utf8))
            items[idx].byteSize = text.utf8.count
        }

        items[idx].rtfData = nil
        scheduleSave()
    }

    /// Strip references to a deleted Space.
    func removeSpaceReference(_ spaceID: UUID) {
        for i in items.indices {
            items[i].spaceIDs.removeAll { $0 == spaceID }
            items[i].spaceNotes?.removeValue(forKey: spaceID.uuidString)
            if items[i].spaceNotes?.isEmpty == true { items[i].spaceNotes = nil }
        }
        scheduleSave()
    }

    /// Retention: drop unprotected items older than `retentionDays`, then enforce the count cap.
    /// Pinned and Space-saved items are never removed.
    func cleanup() {
        let days = settings.retentionDays
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for item in items where !item.isProtected && item.lastUsedAt < cutoff {
                deleteBlob(item)
            }
            items.removeAll { !$0.isProtected && $0.lastUsedAt < cutoff }
        }
        enforceCap()
        scheduleSave()
    }

    // MARK: Helpers

    /// Drop oldest, unprotected items beyond the configured cap.
    private func enforceCap() {
        let cap = max(50, settings.maxItems)
        guard items.count > cap else { return }
        var kept: [ClipItem] = []
        var unprotectedSeen = 0
        for item in items {
            if item.isProtected { kept.append(item); continue }
            unprotectedSeen += 1
            if unprotectedSeen <= cap { kept.append(item) } else { deleteBlob(item) }
        }
        items = kept
    }

    private func deleteBlob(_ item: ClipItem) {
        if let name = item.imageFileName {
            try? FileManager.default.removeItem(at: AppPaths.blobURL(name))
        }
    }

    private func pruneSpaceNotes(at index: Int) {
        guard var notes = items[index].spaceNotes else { return }
        let spaceKeys = Set(items[index].spaceIDs.map(\.uuidString))
        notes = notes.filter { spaceKeys.contains($0.key) }
        items[index].spaceNotes = notes.isEmpty ? nil : notes
    }

    private func byteSize(of d: PasteboardDraft) -> Int {
        (d.text?.utf8.count ?? 0) + (d.rtfData?.count ?? 0) + (d.imagePNG?.count ?? 0)
    }

    private func queueImageTextRecognitionBackfill() {
        for item in items {
            queueImageTextRecognitionIfNeeded(for: item)
        }
    }

    private func queueImageTextRecognitionIfNeeded(for item: ClipItem) {
        guard item.kind == .image,
              item.recognizedText == nil,
              item.imageFileName != nil
        else { return }

        pendingImageTextRecognitionIDs.insert(item.id)
        startImageTextRecognitionWorkerIfNeeded()
    }

    private func startImageTextRecognitionWorkerIfNeeded() {
        guard imageTextRecognitionTask == nil else { return }
        imageTextRecognitionTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let target = nextImageTextRecognitionTarget() else { break }
                let text = await ImageTextRecognizer.recognizeText(at: target.url)
                applyRecognizedImageText(text, to: target.id)
            }

            imageTextRecognitionTask = nil
            if !pendingImageTextRecognitionIDs.isEmpty {
                startImageTextRecognitionWorkerIfNeeded()
            }
        }
    }

    private func nextImageTextRecognitionTarget() -> ImageTextRecognitionTarget? {
        while let id = pendingImageTextRecognitionIDs.first {
            pendingImageTextRecognitionIDs.remove(id)
            guard let item = items.first(where: { $0.id == id }),
                  item.kind == .image,
                  item.recognizedText == nil,
                  let fileName = item.imageFileName
            else { continue }

            return ImageTextRecognitionTarget(id: id, url: AppPaths.blobURL(fileName))
        }
        return nil
    }

    private func applyRecognizedImageText(_ text: String, to id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].kind == .image,
              items[idx].recognizedText == nil
        else { return }

        items[idx].recognizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleSave()
    }

    private func isLink(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace), s.count < 2048 else { return false }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}

private struct ImageTextRecognitionTarget {
    let id: UUID
    let url: URL
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

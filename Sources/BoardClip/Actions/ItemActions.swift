import AppKit
import Photos

/// Per-item smart actions surfaced in the HUD context menu.
@MainActor
enum ItemActions {
    /// Save image clips into the Photos library in one add-only transaction.
    /// On denied/missing permission it opens the Photos privacy pane so the user can grant access.
    static func saveToPhotos(_ items: [ClipItem]) {
        let urls = photoFileNames(in: items)
            .map(AppPaths.blobURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { NSSound.beep(); return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    for url in urls {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                    }
                } completionHandler: { ok, error in
                    DispatchQueue.main.async {
                        if ok {
                            NSSound(named: "Glass")?.play()
                        } else {
                            NSSound.beep()
                            NSLog("[BoardClip] Save to Photos failed: \(error.map { String(describing: $0) } ?? "unknown")")
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    NSSound.beep()
                    NSLog("[BoardClip] Photos access not granted (status \(status.rawValue))")
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }

    static func photoFileNames(in items: [ClipItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard item.kind == .image,
                  let name = item.imageFileName,
                  !name.isEmpty,
                  seen.insert(name).inserted
            else { return nil }
            return name
        }
    }

    /// Open a web search for the clip's text in the default browser.
    static func research(_ item: ClipItem) {
        guard let url = researchURL(for: item.bestPlainText) else { return }
        NSWorkspace.shared.open(url)
    }

    static func researchURL(for text: String) -> URL? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        return components.url
    }

    /// Reveal the first file of a file clip in Finder.
    static func revealInFinder(_ item: ClipItem) {
        guard item.kind == .file, let path = item.fileURLs?.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// In-place text transforms.
    enum Transform: String, CaseIterable, Identifiable {
        case upper = "UPPERCASE"
        case lower = "lowercase"
        case title = "Title Case"
        case trim = "Trim Whitespace"
        case slug = "Slugify"
        case joinLines = "Join Lines"
        var id: String { rawValue }

        func apply(_ s: String) -> String {
            switch self {
            case .upper: return s.uppercased()
            case .lower: return s.lowercased()
            case .title: return s.capitalized
            case .trim: return s.trimmingCharacters(in: .whitespacesAndNewlines)
            case .slug:
                let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 -")
                let cleaned = String(s.lowercased().unicodeScalars.filter { allowed.contains($0) })
                return cleaned.split(whereSeparator: { $0 == " " || $0 == "-" }).joined(separator: "-")
            case .joinLines:
                return s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
            }
        }
    }
}

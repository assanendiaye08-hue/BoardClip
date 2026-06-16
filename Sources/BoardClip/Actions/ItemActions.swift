import AppKit
import Photos

/// Per-item smart actions surfaced in the HUD context menu.
@MainActor
enum ItemActions {
    /// Save an image clip into the Photos library (add-only permission).
    static func saveToPhotos(_ item: ClipItem, completion: ((Bool) -> Void)? = nil) {
        guard item.kind == .image, let name = item.imageFileName else { completion?(false); return }
        let url = AppPaths.blobURL(name)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { completion?(ok) }
            }
        }
    }

    /// Open a web search for the clip's text in the default browser.
    static func research(_ item: ClipItem) {
        let q = item.bestPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
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

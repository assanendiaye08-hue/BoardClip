import Foundation

/// The kind of content a clip holds. Drives icons, filtering and smart actions.
enum ClipKind: String, Codable, CaseIterable, Hashable {
    case text
    case rtf
    case link
    case color
    case image
    case file

    var systemImage: String {
        switch self {
        case .text:  return "text.alignleft"
        case .rtf:   return "textformat"
        case .link:  return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }

    var label: String {
        switch self {
        case .text:  return "Text"
        case .rtf:   return "Rich Text"
        case .link:  return "Link"
        case .color: return "Color"
        case .image: return "Image"
        case .file:  return "File"
        }
    }
}

/// A single saved clipboard entry. Image bytes live on disk (`imageFileName`);
/// everything else is small enough to inline in `history.json`.
struct ClipItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var kind: ClipKind
    var createdAt: Date
    var lastUsedAt: Date
    var pinned: Bool = false
    /// Spaces (durable boards) this clip has been saved into. Non-empty => never auto-cleaned.
    var spaceIDs: [UUID] = []

    var sourceBundleID: String?
    var sourceAppName: String?

    /// Stable hash of the payload, used to de-duplicate re-copies.
    var contentHash: String

    // Payloads (only the relevant ones are set for a given kind)
    var text: String?
    var rtfData: Data?
    var imageFileName: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var fileURLs: [String]?
    var urlString: String?
    var colorHex: String?

    var byteSize: Int = 0

    var isProtected: Bool { pinned || !spaceIDs.isEmpty }

    /// One-line preview used on the card / in lists.
    var preview: String {
        switch kind {
        case .text, .rtf:
            return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .link:
            return urlString ?? text ?? ""
        case .color:
            return colorHex ?? "Color"
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image · \(w)×\(h)" }
            return "Image"
        case .file:
            let urls = fileURLs ?? []
            if urls.count == 1 { return (urls.first.map { URL(fileURLWithPath: $0).lastPathComponent }) ?? "File" }
            return "\(urls.count) files"
        }
    }
}

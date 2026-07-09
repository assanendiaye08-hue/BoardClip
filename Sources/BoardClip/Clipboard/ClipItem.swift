import Foundation
import CryptoKit

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
    /// Optional per-Space note shown on the card instead of the source app label.
    var spaceNotes: [String: String]?

    var sourceBundleID: String?
    var sourceAppName: String?

    /// Stable hash of the payload, used to de-duplicate re-copies.
    var contentHash: String

    // Payloads (only the relevant ones are set for a given kind)
    var text: String?
    var rtfData: Data?
    var imageFileName: String?
    /// Uniform Type Identifier for the stored image bytes, such as `public.png` or `public.jpeg`.
    var imageUTTypeIdentifier: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var fileURLs: [String]?
    var urlString: String?
    var colorHex: String?
    /// Text recognized inside image clips. `nil` means not scanned yet; empty means scanned with no text found.
    var recognizedText: String?

    var byteSize: Int = 0

    var isProtected: Bool { pinned || !spaceIDs.isEmpty }
    var isTextEditable: Bool { kind == .text || kind == .rtf || kind == .link }
    var imageText: String { recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var hasRecognizedImageText: Bool { kind == .image && !imageText.isEmpty }

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

    func note(in spaceID: UUID?) -> String? {
        guard let key = spaceID?.uuidString,
              let note = spaceNotes?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }
}

enum ClipContentHash {
    static func make(kind: ClipKind, seed: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: seed)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum ClipItemCodingKey: String, CodingKey {
    case id, kind, createdAt, lastUsedAt, pinned, spaceIDs, spaceNotes
    case sourceBundleID, sourceAppName, contentHash, text, rtfData
    case imageFileName, imageUTTypeIdentifier, imageWidth, imageHeight
    case fileURLs, urlString, colorHex, recognizedText, byteSize
}

extension ClipItem {
    /// Defaults keep older history files readable when newer releases add stored properties.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ClipItemCodingKey.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ClipKind.self, forKey: .kind)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        spaceIDs = try c.decodeIfPresent([UUID].self, forKey: .spaceIDs) ?? []
        spaceNotes = try c.decodeIfPresent([String: String].self, forKey: .spaceNotes)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        contentHash = try c.decode(String.self, forKey: .contentHash)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        imageUTTypeIdentifier = try c.decodeIfPresent(String.self, forKey: .imageUTTypeIdentifier)
        imageWidth = try c.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try c.decodeIfPresent(Int.self, forKey: .imageHeight)
        fileURLs = try c.decodeIfPresent([String].self, forKey: .fileURLs)
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        recognizedText = try c.decodeIfPresent(String.self, forKey: .recognizedText)
        byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
    }
}

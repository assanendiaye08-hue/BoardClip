import XCTest
import UniformTypeIdentifiers
@testable import BoardClip

final class BoardClipTests: XCTestCase {
    func testLegacyClipDecodingUsesSafeDefaults() throws {
        let data = Data("""
        {
          "kind": "text",
          "createdAt": "2026-01-01T00:00:00Z",
          "lastUsedAt": "2026-01-02T00:00:00Z",
          "contentHash": "legacy",
          "text": "hello"
        }
        """.utf8)

        let item = try JSONDecoder.iso.decode(ClipItem.self, from: data)
        XCTAssertFalse(item.pinned)
        XCTAssertEqual(item.spaceIDs, [])
        XCTAssertEqual(item.byteSize, 0)
        XCTAssertNil(item.imageUTTypeIdentifier)
    }

    func testFuzzyMatchingPrefersContiguousText() {
        let contiguous = Fuzzy.score("clip", in: "clipboard")
        let scattered = Fuzzy.score("clip", in: "cool little input")
        XCTAssertNotNil(contiguous)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(contiguous!, scattered!)
        XCTAssertNil(Fuzzy.score("xyz", in: "clipboard"))
    }

    func testTextTransforms() {
        XCTAssertEqual(ItemActions.Transform.upper.apply("Hello"), "HELLO")
        XCTAssertEqual(ItemActions.Transform.slug.apply("Hello, Board Clip"), "hello-board-clip")
        XCTAssertEqual(ItemActions.Transform.joinLines.apply("one\n two"), "one two")
    }

    func testContentHashIncludesClipKind() {
        let seed = Data("same".utf8)
        XCTAssertNotEqual(
            ClipContentHash.make(kind: .text, seed: seed),
            ClipContentHash.make(kind: .link, seed: seed)
        )
    }

    @MainActor
    func testResearchURLKeepsEntireClipInOneQueryValue() throws {
        let url = try XCTUnwrap(ItemActions.researchURL(for: "alpha & beta = gamma"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "alpha & beta = gamma")])
    }

    @MainActor
    func testJPEGClipUsesJPEGPasteboardType() {
        let item = ClipItem(
            kind: .image,
            createdAt: Date(),
            lastUsedAt: Date(),
            contentHash: "jpeg",
            imageFileName: "image.jpg",
            imageUTTypeIdentifier: UTType.jpeg.identifier
        )
        XCTAssertEqual(item.imagePasteboardType.rawValue, UTType.jpeg.identifier)
    }

    @MainActor
    func testPhotosBatchKeepsOnlyUniqueImageFiles() {
        let first = ClipItem(
            kind: .image,
            createdAt: Date(),
            lastUsedAt: Date(),
            contentHash: "first",
            imageFileName: "first.png"
        )
        let duplicate = ClipItem(
            kind: .image,
            createdAt: Date(),
            lastUsedAt: Date(),
            contentHash: "duplicate",
            imageFileName: "first.png"
        )
        let second = ClipItem(
            kind: .image,
            createdAt: Date(),
            lastUsedAt: Date(),
            contentHash: "second",
            imageFileName: "second.jpg"
        )
        let text = ClipItem(
            kind: .text,
            createdAt: Date(),
            lastUsedAt: Date(),
            contentHash: "text",
            text: "not an image"
        )

        XCTAssertEqual(
            ItemActions.photoFileNames(in: [first, duplicate, text, second]),
            ["first.png", "second.jpg"]
        )
    }
}

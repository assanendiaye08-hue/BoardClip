import Foundation
import UniformTypeIdentifiers

struct ImageDragDescriptor: Equatable {
    let fileURL: URL
    let contentType: UTType
    let suggestedName: String
}

/// Vends stored image clips as copied files for browser upload fields and other macOS drop targets.
enum ImageDragProvider {
    static func descriptor(for item: ClipItem) -> ImageDragDescriptor? {
        descriptor(for: item, isReadableFile: isReadableRegularFile)
    }

    static func descriptor(
        for item: ClipItem,
        isReadableFile: (URL) -> Bool
    ) -> ImageDragDescriptor? {
        guard item.kind == .image,
              let fileName = item.imageFileName,
              !fileName.isEmpty,
              URL(fileURLWithPath: fileName).lastPathComponent == fileName
        else { return nil }

        let fileURL = AppPaths.blobURL(fileName)
        guard isReadableFile(fileURL) else { return nil }

        let contentType = resolvedContentType(for: item, fileURL: fileURL)
        return ImageDragDescriptor(
            fileURL: fileURL,
            contentType: contentType,
            suggestedName: suggestedName(
                for: item.createdAt,
                storedExtension: fileURL.pathExtension,
                contentType: contentType
            )
        )
    }

    static func itemProvider(for descriptor: ImageDragDescriptor) -> NSItemProvider {
        itemProvider(for: descriptor, exportRoot: defaultExportRoot)
    }

    static func itemProvider(for descriptor: ImageDragDescriptor, exportRoot: URL) -> NSItemProvider {
        guard let exportURL = try? makeExportCopy(for: descriptor, in: exportRoot) else {
            NSLog("[BoardClip] Could not create a temporary image drag export")
            return imageItemProvider(fileURL: descriptor.fileURL, descriptor: descriptor)
        }

        let provider = imageItemProvider(fileURL: exportURL, descriptor: descriptor)
        // Browser upload controls commonly require a concrete file URL in addition to image data.
        provider.registerObject(exportURL as NSURL, visibility: .all)
        return provider
    }

    static func cleanupExports() {
        try? FileManager.default.removeItem(at: defaultExportRoot)
    }

    private static func imageItemProvider(
        fileURL: URL,
        descriptor: ImageDragDescriptor
    ) -> NSItemProvider {
        // openInPlace=false makes compatible destinations receive another copy of the export.
        let provider = NSItemProvider(
            contentsOf: fileURL,
            contentType: descriptor.contentType,
            openInPlace: false,
            coordinated: false,
            visibility: .all
        )
        provider.suggestedName = descriptor.suggestedName
        return provider
    }

    private static func makeExportCopy(
        for descriptor: ImageDragDescriptor,
        in exportRoot: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let dragDirectory = exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dragDirectory, withIntermediateDirectories: true)
        let exportURL = dragDirectory.appendingPathComponent(descriptor.suggestedName)
        do {
            try fileManager.copyItem(at: descriptor.fileURL, to: exportURL)
            return exportURL
        } catch {
            try? fileManager.removeItem(at: dragDirectory)
            throw error
        }
    }

    private static var defaultExportRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardClip Drag Exports", isDirectory: true)
            .appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)
    }

    private static func resolvedContentType(for item: ClipItem, fileURL: URL) -> UTType {
        if let identifier = item.imageUTTypeIdentifier,
           let storedType = UTType(identifier),
           storedType.conforms(to: .image) {
            return storedType
        }
        if let extensionType = UTType(filenameExtension: fileURL.pathExtension),
           extensionType.conforms(to: .image) {
            return extensionType
        }
        return .png
    }

    private static func suggestedName(
        for date: Date,
        storedExtension: String,
        contentType: UTType
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let fileExtension = storedExtension.isEmpty
            ? contentType.preferredFilenameExtension ?? "png"
            : storedExtension.lowercased()
        return "BoardClip Image \(formatter.string(from: date)).\(fileExtension)"
    }

    private static func isReadableRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: url.path)
    }
}

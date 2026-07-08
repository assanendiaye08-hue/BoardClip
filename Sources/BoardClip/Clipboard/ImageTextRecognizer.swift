import Foundation
import Vision

/// On-device OCR for image clips. This uses Apple's Vision framework and never uploads images.
enum ImageTextRecognizer {
    static func recognizeText(at url: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(data: data, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }

            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return normalized(lines)
        }.value
    }

    private static func normalized(_ lines: [String]) -> String {
        var seen = Set<String>()
        var ordered: [String] = []

        for line in lines {
            let key = line.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(line)
        }

        return ordered.joined(separator: "\n")
    }
}

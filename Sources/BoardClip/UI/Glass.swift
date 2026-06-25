import SwiftUI
import AppKit

/// Shared design tokens and Liquid Glass helpers.
enum Design {
    static let barCornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 16
    static let cardWidth: CGFloat = 208
    static let cardHeight: CGFloat = 148
    static let panelHeight: CGFloat = 300
    static let panelTopInset: CGFloat = 12       // gap below the menu bar
    static let panelHorizontalInset: CGFloat = 48
    static let maxPanelWidth: CGFloat = 1280
}

extension View {
    /// A subtle tile used for each clip card; brightens + gains an accent ring when selected.
    func clipTile(selected: Bool) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.10)),
                                  lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous))
    }
}

/// Lightweight subsequence fuzzy matcher. Returns nil for no match, else a score (higher = better).
enum Fuzzy {
    static func score(_ needle: String, in haystack: String) -> Int? {
        let n = needle.lowercased()
        if n.isEmpty { return 0 }
        let h = haystack.lowercased()
        if h.contains(n) { return 1000 - (h.count - n.count) } // contiguous match wins
        var hi = h.startIndex
        var matched = 0
        for ch in n {
            guard let found = h[hi...].firstIndex(of: ch) else { return nil }
            matched += 1
            hi = h.index(after: found)
        }
        return matched * 4 - h.count
    }
}

/// Renders a clip's image blob as a thumbnail (lazily loaded from disk).
struct ClipThumbnail: View {
    let fileName: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.05))
            }
        }
        .task(id: fileName) {
            let url = AppPaths.blobURL(fileName)
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}

struct ClipScrollSensitivityTuner: NSViewRepresentable {
    let sensitivity: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        tune(afterMounting: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        tune(afterMounting: nsView)
    }

    private func tune(afterMounting view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = enclosingScrollView(for: view) else { return }
            let speed = max(0.20, min(1.00, sensitivity))
            let lineDistance = CGFloat(28 * speed)
            scrollView.horizontalLineScroll = lineDistance
            scrollView.verticalLineScroll = lineDistance
            scrollView.horizontalPageScroll = Design.cardWidth * CGFloat(speed)
            scrollView.verticalPageScroll = Design.cardWidth * CGFloat(speed)
        }
    }

    private func enclosingScrollView(for view: NSView) -> NSScrollView? {
        var current = view.superview
        while let view = current {
            if let scrollView = view as? NSScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}

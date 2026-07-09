import SwiftUI
import AppKit
import ImageIO

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
    /// A subtle tile used for each clip card. Arrow focus and multi-paste marking are distinct.
    func clipTile(highlighted: Bool, marked: Bool) -> some View {
        let markColor = Color(nsColor: .systemGreen)
        return self
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(tileFill(highlighted: highlighted, marked: marked, markColor: markColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(marked ? AnyShapeStyle(markColor.opacity(0.85)) : AnyShapeStyle(.white.opacity(0.10)),
                                  lineWidth: marked ? 1.5 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                  lineWidth: highlighted ? 3 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous))
    }

    private func tileFill(highlighted: Bool, marked: Bool, markColor: Color) -> AnyShapeStyle {
        if highlighted { return AnyShapeStyle(.tint.opacity(0.18)) }
        if marked { return AnyShapeStyle(markColor.opacity(0.12)) }
        return AnyShapeStyle(.white.opacity(0.06))
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
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 640
                      ] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cgImage, size: .zero)
            }.value
        }
    }
}

struct ClipScrollSensitivityTuner: NSViewRepresentable {
    let sensitivity: Double

    func makeNSView(context: Context) -> ClipScrollSensitivityView {
        let view = ClipScrollSensitivityView(frame: .zero)
        view.sensitivity = sensitivity
        view.connectToScrollView()
        return view
    }

    func updateNSView(_ nsView: ClipScrollSensitivityView, context: Context) {
        nsView.sensitivity = sensitivity
        nsView.connectToScrollView()
    }

    static func dismantleNSView(_ nsView: ClipScrollSensitivityView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

@MainActor
final class ClipScrollSensitivityView: NSView {
    var sensitivity: Double = 0.35 {
        didSet { applyLineScrollTuning() }
    }

    private weak var scrollView: NSScrollView?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connectToScrollView()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func connectToScrollView() {
        DispatchQueue.main.async {
            self.scrollView = self.enclosingScrollView()
            self.applyLineScrollTuning()
            self.startMonitoring()
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scaleScroll(event) ?? event
        }
    }

    private func applyLineScrollTuning() {
        guard let scrollView else { return }
        let speed = CGFloat(clampedSensitivity)
        let lineDistance = 28 * speed
        scrollView.horizontalLineScroll = lineDistance
        scrollView.verticalLineScroll = lineDistance
        scrollView.horizontalPageScroll = Design.cardWidth * speed
        scrollView.verticalPageScroll = Design.cardWidth * speed
    }

    private func scaleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.type == .scrollWheel,
              clampedSensitivity < 0.995,
              let scrollView,
              let window = scrollView.window,
              event.window === window
        else { return event }

        let point = scrollView.convert(event.locationInWindow, from: nil)
        guard scrollView.bounds.contains(point) else { return event }

        let clipView = scrollView.contentView
        let originBeforeScroll = clipView.bounds.origin
        DispatchQueue.main.async { [weak scrollView, weak clipView] in
            guard let scrollView, let clipView else { return }
            let originAfterScroll = clipView.bounds.origin
            let speed = CGFloat(self.clampedSensitivity)
            let scaledOrigin = NSPoint(
                x: originBeforeScroll.x + (originAfterScroll.x - originBeforeScroll.x) * speed,
                y: originBeforeScroll.y + (originAfterScroll.y - originBeforeScroll.y) * speed
            )
            clipView.scroll(to: self.clamped(scaledOrigin, in: clipView))
            scrollView.reflectScrolledClipView(clipView)
        }

        return event
    }

    private var clampedSensitivity: Double {
        max(0.10, min(1.00, sensitivity))
    }

    private func clamped(_ point: NSPoint, in clipView: NSClipView) -> NSPoint {
        guard let documentView = clipView.documentView else { return point }
        let documentBounds = documentView.bounds
        let maxX = max(documentBounds.minX, documentBounds.maxX - clipView.bounds.width)
        let maxY = max(documentBounds.minY, documentBounds.maxY - clipView.bounds.height)
        return NSPoint(
            x: min(max(point.x, documentBounds.minX), maxX),
            y: min(max(point.y, documentBounds.minY), maxY)
        )
    }

    private func enclosingScrollView() -> NSScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? NSScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}

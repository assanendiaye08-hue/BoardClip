import SwiftUI

/// A single clip rendered as a glass tile inside the HUD strip.
struct ClipCardView: View {
    let item: ClipItem
    let index: Int          // 0-based position in the visible list
    let selected: Bool
    let multiSelected: Bool
    let spaceNote: String?

    private var shortcutBadge: String? { index < 9 ? "⌘\(index + 1)" : nil }
    private var hasSpaceNote: Bool { spaceNote != nil }
    private var headerTitle: String { spaceNote ?? item.sourceAppName ?? item.kind.label }
    private var markColor: Color { Color(nsColor: .systemGreen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(width: Design.cardWidth, height: Design.cardHeight, alignment: .topLeading)
        .clipTile(highlighted: selected, marked: multiSelected)
        .clipShape(RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.system(size: 11, weight: hasSpaceNote ? .semibold : .medium))
                .foregroundStyle(hasSpaceNote ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 4)
            if multiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(markColor)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
            }
            if let badge = shortcutBadge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let name = item.imageFileName {
                ClipThumbnail(fileName: name)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                placeholder
            }
        case .color:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(swatchColor)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.2)))
                Text(item.colorHex ?? "")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((item.fileURLs ?? []).prefix(4).enumerated()), id: \.offset) { _, path in
                    Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc")
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
        default:
            Text(item.preview)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
        }
    }

    private var swatchColor: Color {
        if let hex = item.colorHex, let c = NSColor(hex: hex) { return Color(nsColor: c) }
        return .gray
    }

    private var placeholder: some View {
        Image(systemName: item.kind.systemImage)
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

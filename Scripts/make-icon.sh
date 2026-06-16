#!/bin/bash
# Generate Resources/AppIcon.icns from a drawn 1024px master.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
MASTER="$TMP/icon_1024.png"

cat > "$TMP/draw.swift" <<'SWIFT'
import AppKit
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = size * 0.06
let rect = NSRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let path = NSBezierPath(roundedRect: rect, xRadius: size*0.225, yRadius: size*0.225)

let grad = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.55, blue: 1.0, alpha: 1),
                               NSColor(srgbRed: 0.37, green: 0.36, blue: 0.90, alpha: 1)])!
grad.draw(in: path, angle: -90)

// Top glass sheen.
path.addClip()
let sheen = NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0.0)])!
sheen.draw(in: NSRect(x: inset, y: size*0.52, width: size - inset*2, height: size*0.42), angle: -90)

// Clipboard glyph.
let cfg = NSImage.SymbolConfiguration(pointSize: size*0.46, weight: .semibold)
if let sym = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: sym.size)
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let w = sym.size.width, h = sym.size.height
    let dr = NSRect(x: (size-w)/2, y: (size-h)/2 - size*0.01, width: w, height: h)
    NSShadow().shadowColor = NSColor.black.withAlphaComponent(0.25)
    tinted.draw(in: dr, from: .zero, operation: .sourceOver, fraction: 1.0)
}

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swift "$TMP/draw.swift" "$MASTER"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s         "$MASTER" --out "$ICONSET/icon_${s}x${s}.png"   >/dev/null
  sips -z $((s*2)) $((s*2)) "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$TMP"
echo "✓ Resources/AppIcon.icns"

// make_icon.swift — render "Lid Awake" app-icon PNGs (one per size).
//
// Draws a Big-Sur-style rounded-square with a gradient background and a white
// cup-and-saucer glyph (the awake motif used in the menu bar). Usage:
//
//   swiftc -O -o /tmp/make_icon make_icon.swift -framework AppKit
//   /tmp/make_icon <out-dir>
//
// Writes icon_<n>.png for n in {16,32,64,128,256,512,1024}. make-icon.sh turns
// those into AppIcon.icns via iconutil.

import AppKit

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

/// The white cup glyph on its own, on a transparent canvas.
func glyph(_ side: CGFloat) -> NSImage {
    let canvas = NSSize(width: side, height: side)
    let image = NSImage(size: canvas)
    image.lockFocus()
    defer { image.unlockFocus() }

    let cfg = NSImage.SymbolConfiguration(pointSize: side * 0.86, weight: .semibold)
    if let cup = NSImage(systemSymbolName: "cup.and.saucer.fill",
                         accessibilityDescription: "awake")?
        .withSymbolConfiguration(cfg) {
        let g = cup.size
        let origin = NSPoint(x: (side - g.width) / 2, y: (side - g.height) / 2)
        cup.draw(in: NSRect(origin: origin, size: g))
        // Tint only the drawn (opaque) glyph pixels white; the rest stays clear.
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill(using: .sourceAtop)
    }
    return image
}

func icon(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2237                       // ≈ macOS squircle
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Vertical gradient, deep indigo → near-black.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.26, blue: 0.40, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1),
    ])
    gradient?.draw(in: bg, angle: -90)

    // Cup glyph, centered.
    let g = size * 0.62
    let gl = glyph(g)
    gl.draw(in: NSRect(x: (size - g) / 2, y: (size - g) / 2 - size * 0.02, width: g, height: g))

    return image
}

func write(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for s in sizes {
    write(icon(CGFloat(s)), to: "\(outDir)/icon_\(s).png")
}

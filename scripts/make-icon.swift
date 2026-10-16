// Draws the app icon (a green rounded square with a white viewfinder) and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>, then: iconutil -c icns <output.iconset>
// The icon is this project's own drawing, not Greenshot's logo.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // macOS icon grid: a 824 pt rounded square inside the 1024 canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor(srgbRed: 0.30, green: 0.62, blue: 0.20, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.82, blue: 0.33, alpha: 1),
               ending: NSColor(srgbRed: 0.18, green: 0.48, blue: 0.16, alpha: 1))?.draw(in: shape, angle: -90)

    // Viewfinder corners.
    NSColor.white.setStroke()
    let inset = body.insetBy(dx: 170 * s, dy: 170 * s)
    let arm = 130 * s
    let corners = NSBezierPath()
    corners.lineWidth = 46 * s
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    for (x, y, dx, dy) in [(inset.minX, inset.minY, 1.0, 1.0), (inset.maxX, inset.minY, -1.0, 1.0),
                           (inset.minX, inset.maxY, 1.0, -1.0), (inset.maxX, inset.maxY, -1.0, -1.0)] {
        corners.move(to: NSPoint(x: x + dx * arm, y: y))
        corners.line(to: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x, y: y + dy * arm))
    }
    corners.stroke()

    // A selection being drawn in the middle.
    let selection = NSRect(x: body.midX - 150 * s, y: body.midY - 105 * s, width: 300 * s, height: 210 * s)
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: selection, xRadius: 18 * s, yRadius: 18 * s).fill()
    let border = NSBezierPath(roundedRect: selection, xRadius: 18 * s, yRadius: 18 * s)
    border.lineWidth = 22 * s
    border.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard let data = drawIcon(pixels: points * scale) else { fatalError("could not draw \(name)") }
        try data.write(to: output.appendingPathComponent(name))
    }
}
print("Wrote \(output.path)")

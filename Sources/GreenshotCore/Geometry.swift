// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Coordinate helpers shared by the capture overlay and the editor.
///
/// Two global coordinate spaces exist on the Mac: AppKit's (origin at the bottom left of the primary screen, y up)
/// and Quartz's (origin at the top left of the primary screen, y down). Captures, window bounds and the
/// overlay work in Quartz space; only `NSScreen` / `NSWindow` frames use AppKit space.
public enum Geometry {
    public static func quartzRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func quartzPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// The rectangle spanned by two corners given in any order.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// The whole pixels covering `rect` (in points, relative to an image origin) for an image with `scale` pixels per point.
    public static func pixelRect(for rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down)
        let minY = (rect.minY * scale).rounded(.down)
        let maxX = (rect.maxX * scale).rounded(.up)
        let maxY = (rect.maxY * scale).rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A rectangle in pixels of one display's image (origin top left) in global points, for a display at `origin`
    /// with `scale` pixels per point. Used for the text lines and QR codes found on the frozen screens.
    public static func globalRect(fromPixels rect: CGRect, scale: CGFloat, origin: CGPoint) -> CGRect {
        let scale = max(scale, 0.001)
        return CGRect(x: origin.x + rect.minX / scale, y: origin.y + rect.minY / scale,
                      width: rect.width / scale, height: rect.height / scale)
    }

    /// Moves `end` so the rectangle from `start` becomes a square (Shift while drawing a rectangle or ellipse).
    public static func squareEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    /// Snaps the line from `start` to `end` to the nearest multiple of 45 degrees.
    public static func snap45(from start: CGPoint, to end: CGPoint) -> CGPoint {
        snapAngle(from: start, to: end, degrees: 45)
    }

    /// Snaps the line from `start` to `end` to the nearest multiple of `degrees`, keeping its length (Shift while
    /// drawing a line or arrow: 15 degrees, upstream `LineAngleRoundBehavior`).
    public static func snapAngle(from start: CGPoint, to end: CGPoint, degrees: CGFloat) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, degrees > 0 else { return end }
        let step = degrees * .pi / 180
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// `point` mirrored around `center`: the other corner of a box drawn from its centre (Option while drawing,
    /// upstream Ctrl = `ScaleOptions.Centered`).
    public static func mirrored(_ point: CGPoint, around center: CGPoint) -> CGPoint {
        CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }

    /// The crop area dragged from `origin` to `point` (image pixels) in a crop mode, within the image: cutting
    /// columns out spans the whole height, cutting rows out the whole width (upstream `CropContainer.HandleMouseMove`).
    public static func cropSelection(_ mode: CropMode, from origin: CGPoint, to point: CGPoint, imageSize: CGSize) -> CGRect {
        let image = CGRect(origin: .zero, size: imageSize)
        var rect = self.rect(from: origin, to: point)
        switch mode {
        case .vertical: rect = CGRect(x: rect.minX, y: 0, width: rect.width, height: imageSize.height)
        case .horizontal: rect = CGRect(x: 0, y: rect.minY, width: imageSize.width, height: rect.height)
        case .crop, .auto: break
        }
        let clipped = rect.intersection(image)
        return clipped.isNull ? .zero : clipped
    }

    /// How far apart the points of a freehand drawing are at least, image pixels: twice the sensitivity in points
    /// (upstream `FreehandContainer.HandleMouseMove`, `FreehandSensitivity` 1–100). The last point is kept when it is
    /// half of that away.
    public static func freehandSpacing(sensitivity: Int, scale: CGFloat) -> CGFloat {
        CGFloat(2 * min(max(sensitivity, 1), 100)) * scale
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The shortest distance from `p` to the segment `a`-`b`.
    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

/// One display, frozen at the moment a capture started.
public struct FrozenScreen {
    public var displayID: UInt32
    /// The display's bounds in Quartz global coordinates, in points.
    public var frame: CGRect
    /// Pixels per point of `image`.
    public var scale: CGFloat
    public var image: CGImage

    public init(displayID: UInt32, frame: CGRect, scale: CGFloat, image: CGImage) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
        self.image = image
    }
}

/// Cuts a region out of the frozen displays, joining the parts when it spans several displays.
public enum ScreenComposer {
    /// The image of `rect` (Quartz global points) and its pixels per point, or nil when it misses every display.
    /// Parts of `rect` outside every display stay transparent.
    public static func image(of rect: CGRect, from screens: [FrozenScreen]) -> (image: CGImage, scale: CGFloat)? {
        let rect = rect.standardized
        let hits = screens.filter { $0.frame.intersects(rect) }
        guard !hits.isEmpty, rect.width > 0, rect.height > 0 else { return nil }

        if hits.count == 1, let screen = hits.first, screen.frame.contains(rect) {
            let local = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            let bounds = CGRect(x: 0, y: 0, width: screen.image.width, height: screen.image.height)
            let pixels = Geometry.pixelRect(for: local, scale: screen.scale).intersection(bounds)
            guard !pixels.isEmpty, let cropped = screen.image.cropping(to: pixels) else { return nil }
            return (cropped, screen.scale)
        }

        let scale = hits.map(\.scale).max() ?? 1
        let width = Int((rect.width * scale).rounded())
        let height = Int((rect.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        for screen in hits {
            // The context's origin is at the bottom left, Quartz global space has y going down.
            let destination = CGRect(x: (screen.frame.minX - rect.minX) * scale,
                                     y: (rect.maxY - screen.frame.maxY) * scale,
                                     width: screen.frame.width * scale,
                                     height: screen.frame.height * scale)
            context.draw(screen.image, in: destination)
        }
        guard let image = context.makeImage() else { return nil }
        return (image, scale)
    }

    /// The bounding box of all displays, used for "Capture full screen" with every display.
    public static func union(of screens: [FrozenScreen]) -> CGRect {
        screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
}

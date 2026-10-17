// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// The mouse pointer of a capture on its own (upstream `Greenshot.Base/Core/Capture.cs` `Cursor` and `CursorLocation`,
/// a `CapturedCursor`): the editor shows it as an element over the capture without the pointer, so it can be moved or
/// deleted (upstream `Surface(ICapture)` adds a `CursorContainer`).
public struct CapturedPointer: Sendable {
    /// The pointer's picture, `scale` pixels per point.
    public var image: CGImage
    /// Pixels per point of `image`: the same as the capture's.
    public var scale: CGFloat
    /// The pixel of `image` that points (the hot spot), from its top-left corner.
    public var hotSpot: CGPoint
    /// Where the top-left corner of `image` is in the capture, in pixels from the capture's top-left corner: the mouse
    /// position minus the hot spot (upstream `CursorLocation`). The pointer can stick out of the capture.
    public var origin: CGPoint

    public init(image: CGImage, scale: CGFloat, hotSpot: CGPoint, origin: CGPoint) {
        self.image = image
        self.scale = scale
        self.hotSpot = hotSpot
        self.origin = origin
    }

    /// The pointer's picture in the capture, in pixels.
    public var frame: CGRect {
        CGRect(origin: origin, size: CGSize(width: image.width, height: image.height))
    }
}

extension CapturedPointer {
    /// Where the top-left corner of the pointer's picture goes, in pixels of a capture whose top-left corner is at
    /// `imageTopLeft` (Quartz global points) with `scale` pixels per point. `mouse` is in Quartz global points, `hotSpot`
    /// in pixels of the picture. Whole pixels, so the pointer stays sharp.
    public static func origin(mouse: CGPoint, hotSpot: CGPoint, imageTopLeft: CGPoint, scale: CGFloat) -> CGPoint {
        let x = (mouse.x - imageTopLeft.x) * scale - hotSpot.x
        let y = (mouse.y - imageTopLeft.y) * scale - hotSpot.y
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// Where the pointer's picture goes in `ScreenComposer.image(of: rect, from: screens)`, which has `scale` pixels per
    /// point. Follows the composer: inside one display it crops that display's picture on its pixel grid
    /// (`Geometry.pixelRect`), across displays it draws them from the rectangle's corner.
    public static func origin(mouse: CGPoint, hotSpot: CGPoint, rect: CGRect, screens: [FrozenScreen], scale: CGFloat) -> CGPoint {
        let rect = rect.standardized
        let hits = screens.filter { $0.frame.intersects(rect) }
        guard hits.count == 1, let screen = hits.first, screen.frame.contains(rect) else {
            return origin(mouse: mouse, hotSpot: hotSpot, imageTopLeft: rect.origin, scale: scale)
        }
        let local = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let bounds = CGRect(x: 0, y: 0, width: screen.image.width, height: screen.image.height)
        let crop = Geometry.pixelRect(for: local, scale: screen.scale).intersection(bounds)
        // The crop's corner in global points, so the general rule applies.
        let topLeft = CGPoint(x: screen.frame.minX + crop.minX / screen.scale, y: screen.frame.minY + crop.minY / screen.scale)
        return origin(mouse: mouse, hotSpot: hotSpot, imageTopLeft: topLeft, scale: screen.scale)
    }

    /// The pointer touches a capture of `width` × `height` pixels (upstream `Surface(ICapture)` leaves it out otherwise).
    public func touches(width: Int, height: Int) -> Bool {
        frame.intersects(CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Whether the pointer shows in `withPointer`: inside `frame` (pixels, origin top left) its pixels differ from those
    /// of `plain`, the same picture without the pointer. A hidden pointer (while typing, over a full screen video)
    /// leaves both the same.
    public static func isDrawn(plain: CGImage, withPointer: CGImage, in frame: CGRect) -> Bool {
        guard plain.width == withPointer.width, plain.height == withPointer.height else { return false }
        let bounds = CGRect(x: 0, y: 0, width: plain.width, height: plain.height)
        let area = frame.integral.intersection(bounds)
        guard !area.isEmpty, let a = pixels(of: plain, in: area), let b = pixels(of: withPointer, in: area) else { return false }
        return a != b
    }

    /// The RGBA bytes of `area` (pixels, origin top left).
    private static func pixels(of image: CGImage, in area: CGRect) -> [UInt8]? {
        guard let cropped = image.cropping(to: area), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cropped.width
        let height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}

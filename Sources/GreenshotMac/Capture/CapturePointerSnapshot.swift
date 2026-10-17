// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Capture")

/// The mouse pointer at the moment of a capture: its picture and hot spot, and where the mouse was (upstream
/// `Greenshot.Base/Core/WindowCapture.cs` `CaptureCursor`). Taken before the capture screen shows, which sets its own
/// crosshair. ScreenCaptureKit only draws the pointer into the picture, so its picture comes from AppKit.
@MainActor
struct PointerSnapshot {
    let picture: NSImage
    /// Points from the picture's top-left corner.
    let hotSpot: CGPoint
    /// Quartz global points.
    let mouse: CGPoint
    /// System Settings › Accessibility › Display › Pointer size: 1 is normal, up to 4.
    let sizeFactor: CGFloat

    /// The pointer now, nil when macOS doesn't say which one shows.
    static func current() -> PointerSnapshot? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        let picture = cursor.image
        guard picture.size.width > 0, picture.size.height > 0 else { return nil }
        return PointerSnapshot(picture: picture, hotSpot: cursor.hotSpot, mouse: ScreenSpace.mouseLocation,
                               sizeFactor: accessibilitySize)
    }

    /// The pointer size of the accessibility settings, which ScreenCaptureKit draws too; 1 when it can't be read.
    private static var accessibilitySize: CGFloat {
        let value = UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "mouseDriverCursorSize") ?? 0
        return value >= 1 && value <= 4 ? CGFloat(value) : 1
    }

    /// The picture at `scale` pixels per point (times the pointer size) and the hot spot in its pixels.
    func rendered(scale: CGFloat) -> (image: CGImage, hotSpot: CGPoint)? {
        let factor = scale * sizeFactor
        let width = Int((picture.size.width * factor).rounded(.up))
        let height = Int((picture.size.height * factor).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.interpolationQuality = .high
        picture.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return (image, CGPoint(x: hotSpot.x * factor, y: hotSpot.y * factor))
    }

    /// The pointer on its own for a picture that starts at `topLeft` (Quartz global points) with `scale` pixels per
    /// point, when it shows in `withPointer` (compared with `plain`) and touches the picture; nil otherwise.
    func pointer(topLeft: CGPoint, scale: CGFloat, plain: CGImage, withPointer: CGImage) -> CapturedPointer? {
        guard let picture = rendered(scale: scale) else { return nil }
        let origin = CapturedPointer.origin(mouse: mouse, hotSpot: picture.hotSpot, imageTopLeft: topLeft, scale: scale)
        return checked(CapturedPointer(image: picture.image, scale: scale, hotSpot: picture.hotSpot, origin: origin),
                       plain: plain, withPointer: withPointer)
    }

    /// The pointer on its own for `ScreenComposer.image(of: rect, from:)`, see `pointer(topLeft:…)`.
    func pointer(rect: CGRect, screens: [FrozenScreen], scale: CGFloat, plain: CGImage, withPointer: CGImage) -> CapturedPointer? {
        guard let picture = rendered(scale: scale) else { return nil }
        let origin = CapturedPointer.origin(mouse: mouse, hotSpot: picture.hotSpot, rect: rect, screens: screens, scale: scale)
        return checked(CapturedPointer(image: picture.image, scale: scale, hotSpot: picture.hotSpot, origin: origin),
                       plain: plain, withPointer: withPointer)
    }

    private func checked(_ pointer: CapturedPointer, plain: CGImage, withPointer: CGImage) -> CapturedPointer? {
        guard pointer.touches(width: withPointer.width, height: withPointer.height) else { return nil }
        guard CapturedPointer.isDrawn(plain: plain, withPointer: withPointer, in: pointer.frame) else {
            log.debug("The mouse pointer was hidden, the capture has none")
            return nil
        }
        return pointer
    }
}

extension Capture {
    /// Adds the mouse pointer on its own (`pointer`, `imageWithoutPointer`) to a capture of `rect` that was cropped from
    /// `withPointer`, when the pointer shows in it (upstream `Surface(ICapture)` makes it an element then).
    @MainActor
    mutating func addPointer(_ snapshot: PointerSnapshot?, rect: CGRect, plain: [FrozenScreen], withPointer: [FrozenScreen]) {
        guard let snapshot, let without = ScreenComposer.image(of: rect, from: plain) else { return }
        guard without.image.width == image.width, without.image.height == image.height,
              let found = snapshot.pointer(rect: rect, screens: withPointer, scale: scale, plain: without.image, withPointer: image)
        else { return }
        pointer = found
        imageWithoutPointer = without.image
    }
}

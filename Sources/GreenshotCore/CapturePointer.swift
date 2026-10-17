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

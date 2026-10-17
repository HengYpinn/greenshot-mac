// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

extension Annotation {
    /// The captured mouse pointer as an element (upstream `Surface.AddCursorContainer`, `CursorContainer`): its picture
    /// at its place in the capture, at its own size on an image with `documentScale` pixels per point. Nil when the
    /// pointer is outside an image of `imageSize` (upstream `Surface(ICapture)` checks `IntersectsWith`) or its picture
    /// can't be stored.
    public static func pointer(_ pointer: CapturedPointer, documentScale: CGFloat, imageSize: CGSize) -> Annotation? {
        let pointerScale = max(pointer.scale, 0.1)
        guard let data = try? ImageExporter.data(for: pointer.image, format: .png, scale: pointerScale) else { return nil }
        let factor = documentScale / pointerScale
        let size = CGSize(width: CGFloat(pointer.image.width) * factor, height: CGFloat(pointer.image.height) * factor)
        // `origin` is in the capture's pixels, which are the document's.
        let frame = CGRect(origin: pointer.origin, size: size)
        guard frame.intersects(CGRect(origin: .zero, size: imageSize)) else { return nil }
        return Annotation(kind: .cursor, start: frame.origin, end: CGPoint(x: frame.maxX, y: frame.maxY), imageData: data)
    }
}

extension EditorDocument {
    /// Adds the captured mouse pointer as an element, as part of the opened capture: no undo step (upstream adds the
    /// `CursorContainer` while the surface is made). Returns its id; nil when there is no pointer or it is outside the
    /// image.
    @discardableResult
    public func addPointer(_ pointer: CapturedPointer?) -> UUID? {
        guard let pointer, let element = Annotation.pointer(pointer, documentScale: scale, imageSize: imageSize) else {
            return nil
        }
        addOpened([element])
        return element.id
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The operations on the whole image that change its size or orientation: upstream `ResizeEffect`,
/// `RotateEffect`, `ResizeCanvasEffect` and `RemoveTransparencyEffect` (`Greenshot.Base/Effects/*.cs`) and
/// `Surface.Clear` (`Greenshot.Editor/Drawing/Surface.cs`). Sizes are image pixels.
public enum ImageOperations {
    /// Upstream `ResizeEffect` / `ImageHelper.ResizeImage`: `image` scaled to `size` with high quality interpolation.
    public static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = AnnotationRenderer.makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Upstream `RotateEffect` with 90 (clockwise) or 270 (counter-clockwise): the image turned by a quarter.
    public static func rotate(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard let context = AnnotationRenderer.makeContext(width: image.height, height: image.width) else { return nil }
        // In the bitmap's coordinates (origin bottom left): clockwise maps (x, y) to (y, width - x),
        // counter-clockwise to (height - y, x).
        let transform = clockwise
            ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
            : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Upstream `ResizeCanvasEffect` / `ImageHelper.ResizeCanvas`: the image on a canvas that is bigger by the given
    /// pixels on each side, filled with `background` (transparent when nil). Negative values cut the side off.
    public static func resizeCanvas(_ image: CGImage, left: Int, right: Int, top: Int, bottom: Int,
                                    background: CGColor? = nil) -> EffectResult? {
        let width = image.width + left + right
        let height = image.height + top + bottom
        guard width > 0, height > 0, let context = AnnotationRenderer.makeContext(width: width, height: height) else { return nil }
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: CGRect(x: left, y: bottom, width: image.width, height: image.height))
        return context.makeImage().map { EffectResult(image: $0, offset: CGVector(dx: left, dy: top)) }
    }

    /// Upstream `Surface.Clear(Color.Transparent)`: a fully transparent image of the same size.
    public static func cleared(_ image: CGImage) -> CGImage? {
        AnnotationRenderer.makeContext(width: image.width, height: image.height)?.makeImage()
    }

    /// Upstream `RemoveTransparencyEffect`: the image on `color` (white by default), without transparent pixels.
    public static func removingTransparency(_ image: CGImage, color: CGColor = CGColor(gray: 1, alpha: 1)) -> CGImage? {
        guard let context = AnnotationRenderer.makeContext(width: image.width, height: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(color)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Whether the image has an alpha channel with at least one pixel that is not fully opaque (when Remove
    /// Transparency has something to do).
    public static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        guard let context = AnnotationRenderer.makeContext(width: image.width, height: image.height),
              let data = context.data else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * image.height)
        for y in 0..<image.height {
            let row = y * rowBytes
            for x in 0..<image.width where pixels[row + x * 4 + 3] < 255 {
                return true
            }
        }
        return false
    }

    // MARK: - Element geometry

    /// `annotation` with every position (corners, end points, freehand path, speech bubble tail) mapped by `map`.
    /// Text, line widths and font sizes stay as they are, like upstream's transform matrix leaves the fields alone.
    public static func mapPositions(of annotation: Annotation, _ map: (CGPoint) -> CGPoint) -> Annotation {
        var result = annotation
        result.start = map(annotation.start)
        result.end = map(annotation.end)
        result.points = annotation.points.map(map)
        result.tail = annotation.tail.map(map)
        return result
    }

    /// The position of `point` (origin top left) after the image of `size` is turned by a quarter.
    public static func rotated(_ point: CGPoint, imageSize size: CGSize, clockwise: Bool) -> CGPoint {
        clockwise ? CGPoint(x: size.height - point.y, y: point.x) : CGPoint(x: point.y, y: size.width - point.x)
    }
}

// MARK: - The operations on an editor document

extension EditorDocument {
    /// Resizes the image to `size` (pixels) and scales the elements' positions along. Returns false when nothing
    /// changed or the image could not be drawn.
    @discardableResult
    public func resizeImage(to size: CGSize) -> Bool {
        let old = imageSize
        let target = CGSize(width: max(size.width.rounded(), 1), height: max(size.height.rounded(), 1))
        guard target != old, let image = ImageOperations.resize(baseImage, to: target) else { return false }
        let sx = target.width / old.width
        let sy = target.height / old.height
        return replaceImage(with: image) { annotation in
            ImageOperations.mapPositions(of: annotation) { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        }
    }

    /// Turns the image by a quarter; the elements turn along (their text stays upright).
    @discardableResult
    public func rotateImage(clockwise: Bool) -> Bool {
        let size = imageSize
        guard let image = ImageOperations.rotate(baseImage, clockwise: clockwise) else { return false }
        return replaceImage(with: image) { annotation in
            ImageOperations.mapPositions(of: annotation) { ImageOperations.rotated($0, imageSize: size, clockwise: clockwise) }
        }
    }

    /// Grows (or with negative values shrinks) the canvas by pixels on each side; the elements stay on the image.
    @discardableResult
    public func resizeCanvas(left: Int, right: Int, top: Int, bottom: Int, background: CGColor? = nil) -> Bool {
        guard left != 0 || right != 0 || top != 0 || bottom != 0,
              let result = ImageOperations.resizeCanvas(baseImage, left: left, right: right, top: top, bottom: bottom,
                                                        background: background) else { return false }
        return replaceImage(with: result.image, offset: result.offset)
    }

    /// Upstream "Enlarge canvas" (FEATURE-919): 25 pt more transparent canvas on every side.
    @discardableResult
    public func enlargeCanvas(by points: CGFloat = 25) -> Bool {
        let pixels = Int((points * scale).rounded())
        return resizeCanvas(left: pixels, right: pixels, top: pixels, bottom: pixels)
    }

    /// Upstream "Shrink canvas": cuts the fully transparent margin around the image and its elements away.
    /// Returns false when there is no such margin.
    @discardableResult
    public func shrinkCanvas() -> Bool {
        guard let content = AutoCrop.opaqueBounds(of: flattened()) else { return false }
        return crop(to: content)
    }

    /// Upstream "Clear": the image becomes fully transparent, its size and the elements stay.
    @discardableResult
    public func clearImage() -> Bool {
        guard let image = ImageOperations.cleared(baseImage) else { return false }
        return replaceImage(with: image)
    }

    /// Upstream "Remove transparency": puts the image on white. Returns false when it has no transparent pixel.
    @discardableResult
    public func removeTransparency(color: CGColor = CGColor(gray: 1, alpha: 1)) -> Bool {
        guard ImageOperations.hasTransparency(baseImage),
              let image = ImageOperations.removingTransparency(baseImage, color: color) else { return false }
        return replaceImage(with: image)
    }

    /// Upstream `Surface.AutoCrop`: crops to the content found in the image with its elements (within `area` when
    /// given, image pixels). Returns false when there is nothing to crop (upstream "Auto crop not possible").
    @discardableResult
    public func autoCrop(difference: Int, area: CGRect? = nil) -> Bool {
        guard let content = AutoCrop.contentRect(of: flattened(), difference: difference, area: area) else { return false }
        return crop(to: content)
    }

    /// Crops to the rows of `selection` and keeps the whole width.
    @discardableResult
    public func cropRows(of selection: CGRect) -> Bool {
        crop(to: CGRect(x: 0, y: selection.minY, width: imageSize.width, height: selection.height))
    }

    /// Crops to the columns of `selection` and keeps the whole height.
    @discardableResult
    public func cropColumns(of selection: CGRect) -> Bool {
        crop(to: CGRect(x: selection.minX, y: 0, width: selection.width, height: imageSize.height))
    }

    /// Replaces the image with `transform`'s result of the same size (adjust, monochrome, reduce colors).
    @discardableResult
    public func transformImage(_ transform: (CGImage) -> CGImage?) -> Bool {
        guard let image = transform(baseImage) else { return false }
        return replaceImage(with: image)
    }
}

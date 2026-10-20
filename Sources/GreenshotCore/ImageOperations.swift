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
    /// The longest side, pixels, of an image the operations and the effects make: TGA's limit, as for Expand capture
    /// (`EditorDocument.maxPushOutSide`). A recipe can ask for any size; a bigger one fails like a canvas that can't be
    /// drawn, where `Int()` of it would stop the app.
    static let maxSide = 65535

    /// Whether an image can have a side of `length` pixels: at least 1 and at most `maxSide` (NaN and infinity can't).
    static func isDrawable(_ length: CGFloat) -> Bool {
        (1...CGFloat(maxSide)).contains(length)
    }

    /// `points` times `scale` in whole pixels, limited to ±`maxSide`: a recipe can give any number of points, and
    /// `Int()` of a product beyond Int's range would stop the app.
    static func pixels(_ points: Int, scale: CGFloat) -> Int {
        let limit = CGFloat(maxSide)
        let value = (CGFloat(points) * scale).rounded()
        return value.isNaN ? 0 : Int(min(max(value, -limit), limit))
    }

    /// Upstream `ResizeEffect` / `ImageHelper.ResizeImage`: `image` scaled to `size` with high quality interpolation.
    /// Less than a pixel is one; a size no image can have (NaN, infinite, beyond `maxSide`) gives nil.
    public static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let target = CGSize(width: max(size.width.rounded(), 1), height: max(size.height.rounded(), 1))
        guard isDrawable(target.width), isDrawable(target.height) else { return nil }
        let width = Int(target.width)
        let height = Int(target.height)
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
    /// pixels on each side, filled with `background` (transparent when nil). Negative values cut the side off. Nil when
    /// nothing is left or a side would be longer than `maxSide` (margins from a recipe can be anything).
    public static func resizeCanvas(_ image: CGImage, left: Int, right: Int, top: Int, bottom: Int,
                                    background: CGColor? = nil) -> EffectResult? {
        guard let width = sum(image.width, left, right), let height = sum(image.height, top, bottom),
              (1...maxSide).contains(width), (1...maxSide).contains(height),
              let context = AnnotationRenderer.makeContext(width: width, height: height) else { return nil }
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: CGRect(x: left, y: bottom, width: image.width, height: image.height))
        return context.makeImage().map { EffectResult(image: $0, offset: CGVector(dx: left, dy: top)) }
    }

    /// `side + before + after`, nil when it overflows Int.
    private static func sum(_ side: Int, _ before: Int, _ after: Int) -> Int? {
        let (partial, first) = side.addingReportingOverflow(before)
        let (total, second) = partial.addingReportingOverflow(after)
        return first || second ? nil : total
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

    // MARK: - Cut out

    /// Upstream `CutOutHelper.CutOut`: the image without the `size` rows (`horizontal`) or columns from `start`
    /// on, the two parts joined seamlessly. `start` and `size` must be within the image.
    public static func cutOut(_ image: CGImage, start: Int, size: Int, horizontal: Bool) -> CGImage? {
        guard size > 0 else { return image }
        let width = image.width
        let height = image.height
        let length = horizontal ? height : width
        let afterLength = length - start - size
        guard start >= 0, afterLength >= 0 else { return nil }
        let newWidth = horizontal ? width : width - size
        let newHeight = horizontal ? height - size : height
        guard let context = AnnotationRenderer.makeContext(width: newWidth, height: newHeight) else { return nil }
        // The context's origin is at the bottom left; the parts are drawn where their rows or columns end up.
        if start > 0 {
            let before = horizontal ? CGRect(x: 0, y: 0, width: width, height: start) : CGRect(x: 0, y: 0, width: start, height: height)
            if let part = image.cropping(to: before) {
                let target = horizontal ? CGRect(x: 0, y: newHeight - start, width: width, height: start) : before
                context.draw(part, in: target)
            }
        }
        if afterLength > 0 {
            let source = horizontal
                ? CGRect(x: 0, y: start + size, width: width, height: afterLength)
                : CGRect(x: start + size, y: 0, width: afterLength, height: height)
            if let part = image.cropping(to: source) {
                let target = horizontal
                    ? CGRect(x: 0, y: 0, width: width, height: afterLength)
                    : CGRect(x: start, y: 0, width: afterLength, height: height)
                context.draw(part, in: target)
            }
        }
        return context.makeImage()
    }

    /// Where an element is, compared to a strip that is cut out (upstream `Surface.CutOutPlacement`).
    public enum CutOutPlacement: Sendable {
        /// Above or left of the cut: it stays.
        case before
        /// Completely inside the cut: it is removed.
        case inside
        /// Below or right of the cut: it moves with the image.
        case after
        /// Over an edge of the cut: it stays.
        case across
    }

    /// Upstream `Surface.GetCutOutPlacement`: where `bounds` (image pixels) is compared to the `cutSize` rows
    /// (`horizontal`) or columns from `cutStart` on.
    public static func cutOutPlacement(of bounds: CGRect, cutStart: CGFloat, cutSize: CGFloat, horizontal: Bool) -> CutOutPlacement {
        let box = bounds.standardized
        let start = horizontal ? box.minY : box.minX
        let end = horizontal ? box.maxY : box.maxX
        let cutEnd = cutStart + cutSize
        if end <= cutStart { return .before }
        if start >= cutEnd { return .after }
        if start >= cutStart && end <= cutEnd { return .inside }
        return .across
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
            var scaled = ImageOperations.mapPositions(of: annotation) { CGPoint(x: $0.x * sx, y: $0.y * sy) }
            // The room for the shadow of torn edges scales with the image.
            if scaled.kind == .tornEdge { scaled.cutEdges = (scaled.cutEdges ?? CutEdgeLayout()).scaled(x: sx, y: sy) }
            return scaled
        }
    }

    /// Turns the image by a quarter; the elements turn along (their text stays upright, a cut mark across the rows
    /// becomes one across the columns and the other way round). The content of pictures, SVGs, emoji and barcodes turns
    /// too (upstream `VectorGraphicsContainer.Transform`, `ImageContainer.Transform`); the pointer stays upright.
    @discardableResult
    public func rotateImage(clockwise: Bool) -> Bool {
        let size = imageSize
        guard let image = ImageOperations.rotate(baseImage, clockwise: clockwise) else { return false }
        return replaceImage(with: image) { annotation in
            var turned = ImageOperations.mapPositions(of: annotation) { ImageOperations.rotated($0, imageSize: size, clockwise: clockwise) }
            if turned.kind.turnsContentWithImage {
                turned.rotation = Annotation.normalizedRotation(annotation.contentQuarterTurns * 90 + (clockwise ? 90 : 270))
            }
            if turned.kind == .cutMark { turned.verticalCut = !turned.isVerticalCutMark }
            // Torn sides and their room turn with the image.
            if turned.kind == .tornEdge { turned.cutEdges = (turned.cutEdges ?? CutEdgeLayout()).rotated(clockwise: clockwise) }
            return turned
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

    /// Upstream "Shrink canvas" (`ImageEditorForm.ShrinkCanvasToolStripMenuItemClick`): crops the image with its
    /// elements to its content, cutting a border of one color away (colors within `difference`, upstream
    /// `AutoCropDifference`), such as the transparent margin of Enlarge Canvas. Returns false when there is no border.
    @discardableResult
    public func shrinkCanvas(difference: Int = 10) -> Bool {
        guard let content = AutoCrop.contentRect(of: flattened(), difference: difference) else { return false }
        return cropKeepingEdges(to: content)
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
        return cropKeepingEdges(to: content)
    }

    /// Upstream `Surface.ApplyCutOut` (the crop modes Horizontal and Vertical): cuts the rows (`horizontal`) or
    /// the columns of `selection` (image pixels) out of the image and joins the two sides. Elements before the
    /// cut stay, elements inside it are removed, elements after it move along, elements across an edge of it stay.
    ///
    /// With a `cutMark` style other than none, and a cut that is not at an edge of the image, a few rows or
    /// columns of the strip stay for the gap of a cut mark over the joint. The mark gets `markStyle` (the last used
    /// cut mark style: its teeth, colors, shadow and line) with the edges of `cutMark`. Returns false when the
    /// strip is empty or the whole image.
    @discardableResult
    public func cutOut(_ selection: CGRect, horizontal: Bool, cutMark: CutMarkStyle = .none,
                       markStyle: AnnotationStyle = .defaults(for: .cutMark)) -> Bool {
        let size = imageSize
        let strip = selection.standardized.integral.intersection(CGRect(origin: .zero, size: size))
        guard !strip.isEmpty else { return false }
        let cutStart = Int(horizontal ? strip.minY : strip.minX)
        let cutSize = Int(horizontal ? strip.height : strip.width)
        let imageLength = Int(horizontal ? size.height : size.width)
        guard cutSize > 0, cutSize < imageLength else { return false }

        // Only a cut in the middle has a joint to mark; the gap of the mark keeps a part of the strip.
        let marked = cutMark != .none && cutStart > 0 && cutStart + cutSize < imageLength
        let teeth = max(1, Int((CGFloat(markStyle.toothHeight) * scale).rounded()))
        let gap = marked ? min(cutSize, max(2, teeth)) : 0
        guard let image = ImageOperations.cutOut(baseImage, start: cutStart + gap, size: cutSize - gap, horizontal: horizontal) else {
            return false
        }

        let moveBy = CGFloat(cutSize - gap)
        let offset = horizontal ? CGVector(dx: 0, dy: -moveBy) : CGVector(dx: -moveBy, dy: 0)
        func placement(_ element: Annotation) -> ImageOperations.CutOutPlacement {
            ImageOperations.cutOutPlacement(of: element.bounds, cutStart: CGFloat(cutStart), cutSize: CGFloat(cutSize),
                                            horizontal: horizontal)
        }
        let inside = Set(annotations.filter { placement($0) == .inside }.map(\.id))
        remove(inside)
        replaceImage(with: image) { element in
            guard placement(element) == .after else { return element }
            var moved = element
            moved.move(by: offset)
            return moved
        }
        let newSize = imageSize

        if marked {
            var style = markStyle
            style.cutMarkStyle = cutMark
            let bandSize = Int(CutMark.bandSize(toothHeight: CGFloat(teeth), gap: CGFloat(gap)))
            let bandStart = CGFloat(cutStart + gap / 2 - bandSize / 2)
            let bandEnd = bandStart + CGFloat(bandSize)
            var mark = horizontal
                ? Annotation(kind: .cutMark, start: CGPoint(x: 0, y: bandStart), end: CGPoint(x: newSize.width, y: bandEnd), style: style)
                : Annotation(kind: .cutMark, start: CGPoint(x: bandStart, y: 0), end: CGPoint(x: bandEnd, y: newSize.height), style: style)
            mark.verticalCut = !horizontal
            add(mark)
        }
        return true
    }

    /// Upstream `Surface.ApplyElementToImage` ("Apply to the image"): draws the cut marks and torn edges among `ids`
    /// into the image, the way they are saved (cut out parts transparent or in their fill color, with their shadow and
    /// line), and removes them. Returns false when none of `ids` is one.
    @discardableResult
    public func applyToImage(_ ids: Set<UUID>) -> Bool {
        let elements = annotations(ids).filter { AnnotationKind.cutEdgeKinds.contains($0.kind) }
        // The shadow is shared with the cuts that stay elements, like upstream draws the element on its surface.
        guard !elements.isEmpty,
              let image = AnnotationRenderer.flatten(base: baseImage, annotations: elements, scale: scale,
                                                     cutElements: annotations) else { return false }
        remove(Set(elements.map(\.id)))
        return replaceImage(with: image)
    }

    /// Replaces the image with `transform`'s result of the same size (adjust, monochrome, reduce colors).
    @discardableResult
    public func transformImage(_ transform: (CGImage) -> CGImage?) -> Bool {
        guard let image = transform(baseImage) else { return false }
        return replaceImage(with: image)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The effects of the editor's Effects menu (upstream `Greenshot.Base/Effects/*Effect.cs`), with upstream's default
/// settings. They change the capture itself; the elements stay editable and move along when the image grows.
public enum ImageEffect: String, CaseIterable, Sendable {
    case tornEdge, border, dropShadow, grayscale, invert

    public var title: String {
        switch self {
        case .tornEdge: return "Torn Edges"
        case .border: return "Border"
        case .dropShadow: return "Drop Shadow"
        case .grayscale: return "Grayscale"
        case .invert: return "Invert"
        }
    }
}

/// What an effect made: the new image, and where the top left corner of the old image is in it.
public struct EffectResult {
    public var image: CGImage
    public var offset: CGVector
}

/// The image processing of the effects (upstream `Greenshot.Base/Core/ImageHelper.cs`). Upstream's sizes are pixels
/// at 96 DPI, which are points here: they are multiplied with the pixels per point of the capture.
public enum ImageEffects {
    /// `BorderEffect`: 2 pt, black.
    static let borderWidth: CGFloat = 2

    /// `image` with `effect` applied with upstream's default settings, or nil when it could not be drawn. `seed` picks
    /// the torn edges: the same seed gives the same edges (upstream `TornEdgeEffect.Seed`).
    public static func apply(_ effect: ImageEffect, to image: CGImage, scale: CGFloat, seed: UInt64) -> EffectResult? {
        apply(effect, to: image, scale: scale, seed: seed, dropShadow: DropShadowSettings(), tornEdge: TornEdgeSettings())
    }

    /// `image` with `effect` applied with the given settings of the drop shadow and torn edges (upstream
    /// `EditorConfiguration.DropShadowEffectSettings` / `TornEdgeEffectSettings`).
    public static func apply(_ effect: ImageEffect, to image: CGImage, scale: CGFloat, seed: UInt64,
                             dropShadow shadowSettings: DropShadowSettings, tornEdge tornSettings: TornEdgeSettings) -> EffectResult? {
        switch effect {
        case .tornEdge:
            return tornEdge(image, scale: scale, seed: seed, settings: tornSettings)
        case .border:
            return border(image, scale: scale)
        case .dropShadow:
            return dropShadow(image, scale: scale, settings: shadowSettings)
        case .grayscale:
            return mapPixels(image) { r, g, b, _ in
                let gray = grayValue(red: r, green: g, blue: b)
                r = gray
                g = gray
                b = gray
            }.map { EffectResult(image: $0, offset: .zero) }
        case .invert:
            return mapPixels(image) { r, g, b, a in
                // Upstream `CreateNegative`: 1 - color, alpha kept. The pixels are premultiplied, so 1 is the alpha.
                r = a - min(r, a)
                g = a - min(g, a)
                b = a - min(b, a)
            }.map { EffectResult(image: $0, offset: .zero) }
        }
    }

    // MARK: - Effects

    /// Upstream `CreateBorder`: a bigger image with a line around the original.
    static func border(_ image: CGImage, scale: CGFloat) -> EffectResult? {
        let width = (borderWidth * scale).rounded()
        let size = CGSize(width: CGFloat(image.width) + width * 2, height: CGFloat(image.height) + width * 2)
        guard let context = makeContext(size) else { return nil }
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: width / 2, dy: width / 2))
        context.draw(image, in: CGRect(x: width, y: width, width: CGFloat(image.width), height: CGFloat(image.height)))
        return result(context, offset: CGVector(dx: width, dy: width))
    }

    /// Upstream `CreateShadow` (`DropShadowEffect`): a bigger image with a soft shadow. The canvas grows by the shadow
    /// size on every side; the image is drawn at the shadow offset plus size - 1 and the shadow at size, so with the
    /// default offset of -1, -1 the shadow falls 2 pt down right.
    ///
    /// Unlike upstream, which clips the image when a large offset pushes it off that canvas, the canvas grows further
    /// so the whole capture stays.
    public static func dropShadow(_ image: CGImage, scale: CGFloat,
                                  settings: DropShadowSettings = DropShadowSettings()) -> EffectResult? {
        let points = CGFloat(max(settings.size, 0))
        let size = (points * scale).rounded()
        let imageSize = CGSize(width: image.width, height: image.height)
        // Image pixels, origin top left, before the canvas is moved to contain everything.
        let shadowArea = CGRect(origin: .zero, size: CGSize(width: imageSize.width + size * 2, height: imageSize.height + size * 2))
        let imageX = ((CGFloat(settings.offsetX) + points - 1) * scale).rounded()
        let imageY = ((CGFloat(settings.offsetY) + points - 1) * scale).rounded()
        let imageRect = CGRect(origin: CGPoint(x: imageX, y: imageY), size: imageSize)
        let canvas = shadowArea.union(imageRect)
        guard let context = makeContext(canvas.size) else { return nil }
        let origin = CGPoint(x: imageRect.minX - canvas.minX, y: imageRect.minY - canvas.minY)
        let shadowOrigin = CGPoint(x: size - canvas.minX, y: size - canvas.minY)
        let frame = CGRect(x: origin.x, y: canvas.height - origin.y - imageSize.height,
                           width: imageSize.width, height: imageSize.height)
        // The bitmap's y axis points up, so down is negative.
        let darkness = CGFloat(min(max(settings.darkness, 0), 1))
        context.setShadow(offset: CGSize(width: shadowOrigin.x - origin.x, height: origin.y - shadowOrigin.y), blur: size,
                          color: CGColor(gray: 0, alpha: darkness))
        context.draw(image, in: frame)
        return result(context, offset: CGVector(dx: origin.x, dy: origin.y))
    }

    /// Upstream `TornEdgeEffect`: the image torn along the chosen edges, with upstream's default drop shadow when
    /// `settings.shadow` is on (the shadow's own settings of upstream's torn edge dialog are not kept here).
    public static func tornEdge(_ image: CGImage, scale: CGFloat, seed: UInt64,
                                settings: TornEdgeSettings = TornEdgeSettings()) -> EffectResult? {
        guard let torn = tornEdgeImage(image, scale: scale, seed: seed, settings: settings) else { return nil }
        guard settings.shadow else { return EffectResult(image: torn, offset: .zero) }
        return dropShadow(torn, scale: scale)
    }

    /// Upstream `CreateTornEdge`: the image cut out along a zigzag line on the chosen edges, the same size as the
    /// original. Untorn edges stay straight.
    static func tornEdgeImage(_ image: CGImage, scale: CGFloat, seed: UInt64, settings: TornEdgeSettings) -> CGImage? {
        let width = image.width
        let height = image.height
        // The dialog allows 0; upstream's `Random.Next(1, n)` needs n >= 1 and the regions a range of at least 1.
        let tooth = max(Int((CGFloat(settings.toothHeight) * scale).rounded()), 2)
        let horizontalRange = max(Int((CGFloat(settings.horizontalToothRange) * scale).rounded()), 1)
        let verticalRange = max(Int((CGFloat(settings.verticalToothRange) * scale).rounded()), 1)
        var random = SeededRandom(seed: seed)
        func depth() -> Int { Int.random(in: 1..<tooth, using: &random) }
        let horizontalRegions = Int((Double(width) / Double(horizontalRange)).rounded())
        let verticalRegions = Int((Double(height) / Double(verticalRange)).rounded())

        let topLeft = CGPoint(x: 0, y: 0)
        let topRight = CGPoint(x: width, y: 0)
        let bottomLeft = CGPoint(x: 0, y: height)
        let bottomRight = CGPoint(x: width, y: height)

        // Clockwise from the top left, image pixels with the origin at the top left, like upstream.
        var points: [CGPoint] = []
        func add(_ x: Int, _ y: Int) { points.append(CGPoint(x: x, y: y)) }
        if settings.top {
            // The starting point is only torn when the left edge is torn too.
            if settings.left { add(depth(), depth()) } else { points.append(topLeft) }
            for i in stride(from: 1, to: horizontalRegions - 1, by: 1) { add(i * horizontalRange, depth()) }
            add(width - depth(), depth())
        } else {
            points += [topLeft, topRight]
        }
        if settings.right {
            for i in stride(from: 1, to: verticalRegions - 1, by: 1) { add(width - depth(), i * verticalRange) }
            add(width - depth(), height - depth())
        } else {
            // Correct the previous end point, then a straight edge.
            points[points.count - 1] = topRight
            points.append(bottomRight)
        }
        if settings.bottom {
            for i in stride(from: 1, to: horizontalRegions - 1, by: 1) { add(width - i * horizontalRange, height - depth()) }
            add(depth(), height - depth())
        } else {
            points[points.count - 1] = bottomRight
            points.append(bottomLeft)
        }
        if settings.left {
            for _ in stride(from: 1, to: verticalRegions - 1, by: 1) {
                add(depth(), Int(points[points.count - 1].y) - verticalRange)
            }
        } else {
            points[points.count - 1] = bottomLeft
            points.append(topLeft)
        }
        // Upstream ends where it started by replacing the last point.
        points[points.count - 1] = points[0]

        let size = CGSize(width: width, height: height)
        guard let context = makeContext(size) else { return nil }
        let path = CGMutablePath()
        path.addLines(between: points, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        path.closeSubpath()
        context.addPath(path)
        context.clip()
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: - Helpers

    /// Upstream `CreateGrayscale`'s color matrix. Written as typed steps: as one expression inside the pixel closure,
    /// Swift 6.1 (Xcode 16) gives up type-checking it.
    static func grayValue(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let r: Double = 0.3 * Double(red)
        let g: Double = 0.59 * Double(green)
        let b: Double = 0.11 * Double(blue)
        return UInt8(min((r + g + b).rounded(), 255))
    }

    static func makeContext(_ size: CGSize) -> CGContext? {
        AnnotationRenderer.makeContext(width: Int(size.width), height: Int(size.height))
    }

    static func result(_ context: CGContext, offset: CGVector) -> EffectResult? {
        context.makeImage().map { EffectResult(image: $0, offset: offset) }
    }

    /// The image with `transform` applied to every pixel's premultiplied red, green and blue (alpha is passed along).
    static func mapPixels(_ image: CGImage, _ transform: (inout UInt8, inout UInt8, inout UInt8, UInt8) -> Void) -> CGImage? {
        guard let context = AnnotationRenderer.makeContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * image.height)
        for y in 0..<image.height {
            var i = y * rowBytes
            for _ in 0..<image.width {
                transform(&pixels[i], &pixels[i + 1], &pixels[i + 2], pixels[i + 3])
                i += 4
            }
        }
        return context.makeImage()
    }
}

extension EditorDocument {
    /// Applies an effect with the given settings of the drop shadow and the torn edges.
    @discardableResult
    public func apply(_ effect: ImageEffect, dropShadow: DropShadowSettings, tornEdge: TornEdgeSettings,
                      seed: UInt64 = .random(in: .min ... .max)) -> Bool {
        guard let result = ImageEffects.apply(effect, to: baseImage, scale: scale, seed: seed,
                                              dropShadow: dropShadow, tornEdge: tornEdge) else { return false }
        return replaceImage(with: result.image, offset: result.offset)
    }
}

/// A random number generator that repeats its numbers for the same seed (SplitMix64), for reproducible torn edges.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

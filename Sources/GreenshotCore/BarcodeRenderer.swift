// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

private let log = Log("Barcode")

/// Where the modules of a code go in an element's box (upstream `ZxingBarcodeGenerator.RenderMatrix` and
/// `BarcodeContainer.Draw`): a matrix code keeps square modules and is centred, a bar code fills the box, its bars as
/// tall as the box. The margin (quiet zone) is in modules.
public struct BarcodeLayout: Equatable, Sendable {
    /// The code with its quiet zone: the background.
    public let frame: CGRect
    /// The top left of the first module.
    public let origin: CGPoint
    public let moduleWidth: CGFloat
    public let moduleHeight: CGFloat

    public init(matrix: BarcodeMatrix, margin: Int, is2D: Bool, in box: CGRect) {
        let quiet = CGFloat(max(margin, 0))
        let columns = CGFloat(matrix.width) + 2 * quiet
        guard columns > 0, box.width > 0, box.height > 0 else {
            self.init(frame: box, origin: box.origin, moduleWidth: 0, moduleHeight: 0)
            return
        }
        if is2D {
            let rows = CGFloat(matrix.height) + 2 * quiet
            let module = min(box.width / columns, box.height / max(rows, 1))
            let size = CGSize(width: columns * module, height: rows * module)
            let frame = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            let origin = CGPoint(x: frame.minX + quiet * module, y: frame.minY + quiet * module)
            self.init(frame: frame, origin: origin, moduleWidth: module, moduleHeight: module)
        } else {
            let module = box.width / columns
            self.init(frame: box, origin: CGPoint(x: box.minX + quiet * module, y: box.minY), moduleWidth: module,
                      moduleHeight: box.height / CGFloat(max(matrix.height, 1)))
        }
    }

    init(frame: CGRect, origin: CGPoint, moduleWidth: CGFloat, moduleHeight: CGFloat) {
        self.frame = frame
        self.origin = origin
        self.moduleWidth = moduleWidth
        self.moduleHeight = moduleHeight
    }

    /// The box of the module at column `x`, row `y`.
    public func module(x: Int, y: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(x) * moduleWidth, y: origin.y + CGFloat(y) * moduleHeight,
               width: moduleWidth, height: moduleHeight)
    }
}

extension BarcodeSpec {
    /// The modules of the code (cached: drawing is called for every change on the canvas). Throws why the text can't
    /// be encoded.
    public func matrix() throws -> BarcodeMatrix {
        try BarcodeMatrixCache.matrix(symbology, payload: payload)
    }

    /// The size of a new element in points: upstream inserts its preview bitmap, 210 × 210 for a matrix code (here with
    /// the code's aspect ratio) and 330 × 100 for a bar code.
    public var defaultSize: CGSize {
        guard symbology.is2D else { return CGSize(width: 330, height: 100) }
        guard let matrix = try? matrix(), matrix.width > 0, matrix.height > 0 else { return CGSize(width: 210, height: 210) }
        let quiet = 2 * CGFloat(margin)
        let aspect = (CGFloat(matrix.width) + quiet) / (CGFloat(matrix.height) + quiet)
        return aspect >= 1 ? CGSize(width: 210, height: (210 / aspect).rounded())
            : CGSize(width: (210 * aspect).rounded(), height: 210)
    }

    /// The box of an edited element that had `old` as its spec and `box` as its bounds: the same place; a bar code
    /// keeps its box, a matrix code its width (with its new aspect ratio); a switch between the two gets the new
    /// default size (`scale` pixels per point).
    public func editedBox(from box: CGRect, old: BarcodeSpec?, scale: CGFloat) -> CGRect {
        let wasMatrix = old?.symbology.is2D
        if wasMatrix == false && !symbology.is2D { return box }
        let size = defaultSize
        if wasMatrix == true && symbology.is2D && size.width > 0 {
            return CGRect(x: box.minX, y: box.minY, width: box.width, height: (box.width * size.height / size.width).rounded())
        }
        return CGRect(x: box.minX, y: box.minY, width: size.width * scale, height: size.height * scale)
    }
}

extension Annotation {
    /// A new barcode element showing `spec`, its top left at `origin`, at its default size on an image with `scale`
    /// pixels per point, made smaller to fit in `limit` (image pixels).
    public static func barcodeElement(_ spec: BarcodeSpec, at origin: CGPoint, scale: CGFloat, fitting limit: CGSize? = nil) -> Annotation {
        let points = spec.defaultSize
        var size = CGSize(width: points.width * scale, height: points.height * scale)
        if let limit, limit.width > 0, limit.height > 0, size.width > limit.width || size.height > limit.height {
            let shrink = min(limit.width / size.width, limit.height / size.height)
            size = CGSize(width: size.width * shrink, height: size.height * shrink)
        }
        var element = Annotation(kind: .barcode, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height))
        element.barcode = spec
        return element
    }
}

extension AnnotationRenderer {
    /// Draws a barcode element from its spec, at its bounds (upstream `BarcodeContainer.Draw`, which re-renders its
    /// bitmap at the new size; here the modules are drawn as shapes, so they stay sharp at any size).
    static func drawBarcode(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        guard let spec = a.barcode else { return }
        let box = a.bounds
        guard box.width >= 1, box.height >= 1 else { return }
        withShadow(a.style.shadow, in: context, scale: scale) {
            drawBarcode(spec, in: box, context: context, lineWidth: scale)
        }
    }

    /// Draws `spec` into `box` of a context with the origin at the top left. A text the format can't hold is drawn as
    /// its background with a cross, so the element stays visible and can be fixed or deleted.
    static func drawBarcode(_ spec: BarcodeSpec, in box: CGRect, context: CGContext, lineWidth: CGFloat) {
        guard let matrix = try? spec.matrix() else {
            context.setFillColor(spec.background.cgColor)
            context.fill(box)
            context.setStrokeColor(spec.foreground.cgColor)
            context.setLineWidth(lineWidth)
            context.strokeLineSegments(between: [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY),
                                                 CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY)])
            return
        }
        let layout = BarcodeLayout(matrix: matrix, margin: spec.margin, is2D: spec.symbology.is2D, in: box)
        if spec.background.isVisible {
            context.setFillColor(spec.background.cgColor)
            context.fill(layout.frame)
        }
        guard spec.foreground.isVisible else { return }
        let square = spec.roundedDots && spec.symbology.hasRoundedDots ? squareModules(of: spec.symbology, matrix) : nil
        context.addPath(barcodePath(matrix, layout: layout, squareModules: square))
        context.setFillColor(spec.foreground.cgColor)
        // One fill for every module, so neighbouring modules have no seams between them.
        context.fillPath()
    }

    /// The dark modules as one path: runs of a row as rectangles. With `squareModules` the others are dots of 95 % of a
    /// module, like upstream's `FillEllipse(px + 0.25, py + 0.25, scale - 0.5)`; the modules it picks stay square.
    static func barcodePath(_ matrix: BarcodeMatrix, layout: BarcodeLayout, squareModules: ((Int, Int) -> Bool)? = nil) -> CGPath {
        let path = CGMutablePath()
        func isDot(_ x: Int, _ y: Int) -> Bool {
            guard let squareModules else { return false }
            return !squareModules(x, y)
        }
        for y in 0..<matrix.height {
            var x = 0
            while x < matrix.width {
                guard matrix[x, y] else {
                    x += 1
                    continue
                }
                if isDot(x, y) {
                    let dot = layout.module(x: x, y: y)
                    path.addEllipse(in: dot.insetBy(dx: dot.width * 0.025, dy: dot.height * 0.025))
                    x += 1
                    continue
                }
                var end = x + 1
                while end < matrix.width, matrix[end, y], !isDot(end, y) {
                    end += 1
                }
                let first = layout.module(x: x, y: y)
                path.addRect(CGRect(x: first.minX, y: first.minY, width: CGFloat(end - x) * layout.moduleWidth,
                                    height: layout.moduleHeight))
                x = end
            }
        }
        return path
    }

    /// The modules that stay square among round dots, so that scanners still find the code: the three 7 × 7 finder
    /// patterns of a QR code (upstream `RenderMatrix`), and, unlike upstream (whose round Aztec and Data Matrix codes
    /// don't scan), the bull's eye of an Aztec code and the finder and timing edges of every Data Matrix region.
    static func squareModules(of symbology: BarcodeSymbology, _ matrix: BarcodeMatrix) -> (Int, Int) -> Bool {
        switch symbology {
        case .qrCode:
            return { x, y in isQRFinder(x: x, y: y, matrix: matrix) }
        case .aztec:
            // The core of a full-range code: 15 × 15 around the centre (a compact code's is 11 × 11).
            let centerX = matrix.width / 2
            let centerY = matrix.height / 2
            return { x, y in abs(x - centerX) <= 7 && abs(y - centerY) <= 7 }
        case .dataMatrix:
            let region = DataMatrixEncoder.regionSide(symbolSide: matrix.width) + 2
            return { x, y in x % region == 0 || x % region == region - 1 || y % region == 0 || y % region == region - 1 }
        default:
            return { _, _ in true }
        }
    }

    /// Whether a module is part of one of the three 7 × 7 finder patterns of a QR code (top left, top right, bottom
    /// left).
    static func isQRFinder(x: Int, y: Int, matrix: BarcodeMatrix) -> Bool {
        let left = x < 7
        let top = y < 7
        let right = x >= matrix.width - 7
        let bottom = y >= matrix.height - 7
        return (left && top) || (right && top) || (left && bottom)
    }

    /// `spec` drawn alone into an image of `size` pixels (the dialog's preview). Throws why the text can't be encoded.
    public static func barcodeImage(_ spec: BarcodeSpec, size: CGSize) throws -> CGImage {
        _ = try spec.matrix()
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = makeContext(width: width, height: height) else { throw BarcodeError.tooLong }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        drawBarcode(spec, in: CGRect(x: 0, y: 0, width: width, height: height), context: context, lineWidth: 1)
        guard let image = context.makeImage() else { throw BarcodeError.tooLong }
        return image
    }
}

/// The matrices of the codes drawn lately, by format and text, failures included (so an invalid element isn't
/// encoded again on every redraw).
enum BarcodeMatrixCache {
    private final class Entry {
        let result: Result<BarcodeMatrix, Error>
        init(_ result: Result<BarcodeMatrix, Error>) { self.result = result }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 64
        return cache
    }()

    static func matrix(_ symbology: BarcodeSymbology, payload: String) throws -> BarcodeMatrix {
        let key = "\(symbology.rawValue):\(payload)" as NSString
        if let entry = cache.object(forKey: key) { return try entry.result.get() }
        let result = Result { try BarcodeGenerator.matrix(symbology, payload: payload) }
        if case .failure(let error) = result {
            log.debug("No \(symbology.rawValue) code for \(payload.count) characters: \(error.localizedDescription)")
        }
        cache.setObject(Entry(result), forKey: key)
        return try result.get()
    }
}

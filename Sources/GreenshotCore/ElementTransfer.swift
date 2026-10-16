// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Elements on their way through the clipboard or a `.greenshot-elements` file: upstream's
/// `DrawableContainerClipboard` and `Surface.SaveElementsToStream` / `LoadElementsFromStream`, which serialize the
/// element list. Here it is JSON of the elements with the pixels per point of the image they were on.
public struct ElementTransfer: Codable, Equatable {
    /// The pasteboard type of copied elements.
    public static let pasteboardType = "io.github.greenshot-mac.elements"
    /// The file extension of saved elements.
    public static let fileExtension = "greenshot-elements"

    public var version: Int
    /// The document the elements were copied from, so pasting them back moves them a little.
    public var sourceDocument: UUID?
    /// Pixels per point of the image the elements were on.
    public var scale: CGFloat
    public var elements: [Annotation]

    public init(elements: [Annotation], scale: CGFloat, sourceDocument: UUID? = nil) {
        version = 1
        self.sourceDocument = sourceDocument
        self.scale = scale
        self.elements = elements
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> ElementTransfer? {
        guard let transfer = try? JSONDecoder().decode(ElementTransfer.self, from: data), transfer.scale > 0 else { return nil }
        return transfer
    }

    /// All elements of a document, for a `.greenshot-elements` file (upstream `Surface.SaveElementsToStream`).
    public static func file(of document: EditorDocument) -> ElementTransfer {
        ElementTransfer(elements: document.annotations, scale: document.scale)
    }

    /// Adds the elements of a file to `document` as one undo step (upstream `Surface.LoadElementsFromStream`), at
    /// their saved place, moved into the image when it is smaller. Returns the added elements.
    @discardableResult
    public func load(into document: EditorDocument) -> [Annotation] {
        let added = placed(in: document.imageSize, scale: document.scale, documentID: document.id)
        document.change { document.add(added) }
        return added
    }

    /// The elements as new elements of a document: with new ids, at the pixels per point of the document, and placed
    /// like upstream's `Surface.PasteElementFromClipboard`.
    /// - Parameters:
    ///   - size: the image size of the target document (pixels).
    ///   - scale: its pixels per point.
    ///   - documentID: the target document; pasting into the source moves the elements by 10 points.
    ///   - point: where to put the top left of the elements (the mouse), or nil to keep their position.
    public func placed(in size: CGSize, scale: CGFloat, documentID: UUID?, at point: CGPoint? = nil) -> [Annotation] {
        let factor = scale / self.scale
        var result = elements.map { $0.withNewID().scaled(by: factor) }
        guard let first = result.first else { return [] }
        let union = result.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
        let canvas = CGRect(origin: .zero, size: size)
        let delta: CGVector
        if let point {
            delta = CGVector(dx: point.x - union.minX, dy: point.y - union.minY)
        } else {
            delta = Self.pasteOffset(for: union, in: canvas, sameDocument: documentID != nil && documentID == sourceDocument,
                                     step: 10 * scale)
        }
        for index in result.indices { result[index].move(by: delta) }
        return result
    }

    /// Upstream's offset of pasted elements: 10, 10 into their own surface, nothing into another one; and back
    /// into the image when that puts them outside it.
    static func pasteOffset(for bounds: CGRect, in canvas: CGRect, sameDocument: Bool, step: CGFloat) -> CGVector {
        var offset = sameDocument ? CGVector(dx: step, dy: step) : .zero
        let fits = bounds.width < canvas.width && bounds.height < canvas.height
        if !fits {
            let location = CGPoint(x: bounds.minX + offset.dx, y: bounds.minY + offset.dy)
            if !canvas.contains(location) {
                offset = sameDocument ? CGVector(dx: -step, dy: -step)
                    : CGVector(dx: -bounds.minX + step, dy: -bounds.minY + step)
            }
            return offset
        }
        let moved = bounds.offsetBy(dx: offset.dx, dy: offset.dy)
        guard !canvas.contains(moved) else { return offset }
        if sameDocument { return CGVector(dx: -step, dy: -step) }
        // Most likely a smaller image: move it in from the right and the bottom, but not out at the left or the top.
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if bounds.maxX > canvas.maxX {
            dx = canvas.maxX - bounds.maxX
            if bounds.minX + dx < 0 { dx -= bounds.minX + dx }
        }
        if bounds.maxY > canvas.maxY {
            dy = canvas.maxY - bounds.maxY
            if bounds.minY + dy < 0 { dy -= bounds.minY + dy }
        }
        return CGVector(dx: dx, dy: dy)
    }
}

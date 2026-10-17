// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The cut marks and torn edges of a drawing, for their shared shadow: port of upstream
/// `Greenshot.Editor/Drawing/CutShadow.cs` (commit 9f6726c0). They cut parts out of the image, wherever they overlap:
/// the shadow is cast by what is left of the image, which is the same for all of them, and every part of a cut area
/// gets the shadow only once, from the cut drawn last there. The line along an edge doesn't show where another cut took
/// the image away. With a single cut this is exactly the element's own shadow.
struct CutShadow {
    /// What one element cuts out of the image (image pixels, origin top left).
    struct Cut {
        let id: UUID
        /// The area that is cut out, filled with `areaRule`.
        let area: CGPath
        let areaRule: CGPathFillRule
        /// The rest of the image, filled with `restRule`.
        let rest: CGPath
        let restRule: CGPathFillRule
        /// The shape the element draws, so it is made once per drawing.
        let cutMark: CutMark.Shape?
        let tornEdge: TornEdge.Shape?
    }

    /// The cuts in the order they are drawn (upstream `GetCuts`).
    let cuts: [Cut]
    let canvas: CGRect

    /// The cuts among `annotations` on a canvas of `canvas` (image pixels); `scale` is pixels per point.
    init(_ annotations: [Annotation], canvas: CGRect, scale: CGFloat) {
        self.canvas = canvas
        cuts = annotations.compactMap { Self.cut(of: $0, canvas: canvas, scale: scale) }
    }

    /// Upstream `CreateCutPath`; nil when the element cuts nothing out (style None, an empty band, no torn side).
    private static func cut(of a: Annotation, canvas: CGRect, scale: CGFloat) -> Cut? {
        switch a.kind {
        case .cutMark:
            guard let shape = CutMark.shape(of: a, imageSize: canvas.size, scale: scale) else { return nil }
            let rest = CGMutablePath()
            rest.addRect(canvas)
            rest.addPath(shape.gap)
            return Cut(id: a.id, area: shape.gap, areaRule: .winding, rest: rest, restRule: .evenOdd, cutMark: shape,
                       tornEdge: nil)
        case .tornEdge:
            guard let shape = TornEdge.shape(of: a, imageSize: canvas.size, scale: scale) else { return nil }
            return Cut(id: a.id, area: shape.tornOff, areaRule: .evenOdd, rest: shape.kept, restRule: .winding,
                       cutMark: nil, tornEdge: shape)
        default:
            return nil
        }
    }

    /// The cut of the element `id`.
    func cut(_ id: UUID) -> Cut? {
        cuts.first { $0.id == id }
    }

    /// Whether the element `id` is the only cut: then its shadow and line are its own.
    func isAlone(_ id: UUID) -> Bool {
        !cuts.contains { $0.id != id }
    }

    /// Upstream `CutShadow.Draw` with `CreateShadow`: the shadow of what is left of the image (the canvas without every
    /// cut) in the area of the element `id`, without the areas of the cuts drawn after it; as dark, soft and far as
    /// `layout` says.
    func drawShadow(of id: UUID, layout: CutEdgeLayout, in context: CGContext, scale: CGFloat) {
        guard let index = cuts.firstIndex(where: { $0.id == id }) else { return }
        let own = cuts[index]
        context.saveGState()
        context.addPath(own.area)
        context.clip(using: own.areaRule)
        for later in cuts[(index + 1)...] {
            context.addPath(later.rest)
            context.clip(using: later.restRule)
        }
        AnnotationRenderer.setCutShadow(layout, in: context, scale: scale)
        // What casts the shadow: the canvas with every cut cleared. It never shows itself, the clip is inside a cut.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(canvas)
        context.setBlendMode(.clear)
        for cut in cuts {
            context.addPath(cut.area)
            context.fillPath(using: cut.areaRule)
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Upstream `CutShadow.ExcludeOtherCuts`: leaves out the areas the other elements cut out, so the line along the
    /// edges of the element `id` doesn't show in another gap.
    func clipOutOtherCuts(than id: UUID, in context: CGContext) {
        for cut in cuts where cut.id != id {
            context.addPath(cut.rest)
            context.clip(using: cut.restRule)
        }
    }
}

extension CutMark {
    /// The shape of a cut mark element on an image of `imageSize`; `scale` is pixels per point.
    static func shape(of a: Annotation, imageSize: CGSize, scale: CGFloat) -> Shape? {
        let style = a.style
        return shape(band: band(of: a, imageSize: imageSize), style: style.cutMarkStyle,
                     toothHeight: CGFloat(style.toothHeight) * scale, toothRange: CGFloat(style.toothRange) * scale,
                     seed: seed(of: a), vertical: a.isVerticalCutMark)
    }
}

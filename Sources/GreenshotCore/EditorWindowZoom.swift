// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// The editor's zoom steps and where a zoom keeps the view (upstream `Greenshot.Editor/Forms/ImageEditorForm.cs`
/// `ZOOM_VALUES`, `ZoomInMenuItemClick`, `ZoomOutMenuItemClick`, `ZoomSetValue`).
public enum EditorWindowZoom {
    /// Upstream's zoom values, ascending: ¼, ½, ⅔, ¾, 1, 2, 3, 4, 6.
    public static let ladder: [CGFloat] = [1.0 / 4, 1.0 / 2, 2.0 / 3, 3.0 / 4, 1, 2, 3, 4, 6]
    /// The ladder as percentages, for the zoom menus (an item's tag); 66 stands for two thirds.
    public static let presetPercents = [25, 50, 66, 75, 100, 200, 300, 400, 600]

    /// Two magnifications closer than this count as the same (a pinch or a fit gives arbitrary values).
    static let tolerance: CGFloat = 0.005

    /// The factor of a preset percentage; 66 % is two thirds, like upstream's.
    public static func factor(percent: Int) -> CGFloat {
        percent == 66 ? 2.0 / 3.0 : CGFloat(percent) / 100
    }

    /// Whether the magnification is that preset (its menu item gets the check mark).
    public static func matches(_ magnification: CGFloat, percent: Int) -> Bool {
        abs(magnification - factor(percent: percent)) < tolerance
    }

    /// The next step up from any magnification; the largest step stays.
    public static func zoomedIn(from magnification: CGFloat) -> CGFloat {
        ladder.first { $0 > magnification + tolerance } ?? ladder[ladder.count - 1]
    }

    /// The next step down from any magnification; the smallest step stays.
    public static func zoomedOut(from magnification: CGFloat) -> CGFloat {
        ladder.last { $0 < magnification - tolerance } ?? ladder[0]
    }

    /// The title of the status bar's zoom button, e.g. "100%" (upstream `zoomStatusDropDownBtn`); a preset shows its
    /// own percentage, so two thirds is "66%" as in the menu.
    public static func label(_ magnification: CGFloat) -> String {
        if let preset = presetPercents.first(where: { matches(magnification, percent: $0) }) { return "\(preset)%" }
        return "\(Int((magnification * 100).rounded()))%"
    }

    /// The point of the image (in its unzoomed coordinates, top left origin) to show in the middle of the view after
    /// a zoom by key or menu (upstream `ZoomSetValue`). Zooming in goes to the visible part of the selection; without
    /// one, an image that fits the view in a direction keeps its top or left edge in view ("less disorienting for
    /// screenshots"). Otherwise, and when zooming out, the middle of what is visible stays in the middle.
    /// - Parameters:
    ///   - viewport: the part of the image coordinate space the view shows (it can be larger than the image).
    ///   - imageSize: the image in the same units.
    ///   - selection: the box around the selected elements, if any.
    public static func anchor(viewport: CGRect, imageSize: CGSize, selection: CGRect?, zoomingIn: Bool) -> CGPoint {
        let image = CGRect(origin: .zero, size: imageSize)
        var visible = viewport.intersection(image)
        if visible.isNull { visible = image }
        let middle = CGPoint(x: visible.midX, y: visible.midY)
        guard zoomingIn else { return middle }
        if let selection {
            let part = selection.intersection(visible)
            if !part.isNull { return CGPoint(x: part.midX, y: part.midY) }
        }
        var point = middle
        if imageSize.width <= viewport.width { point.x = 0 }
        if imageSize.height <= viewport.height { point.y = 0 }
        return point
    }
}

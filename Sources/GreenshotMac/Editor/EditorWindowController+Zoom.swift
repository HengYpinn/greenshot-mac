// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Zoom (View menu, the status bar's zoom button, ⌘ with the scroll wheel): upstream's zoom steps and where a zoom
/// keeps the view (`ImageEditorForm` `ZoomInMenuItemClick`, `ZoomOutMenuItemClick`, `ZoomSetValue`, `PanelMouseWheel`).
/// Pinch zooming is the scroll view's own.
extension EditorWindowController {
    /// One step up the zoom ladder (¼ … 6×).
    @objc func zoomIn(_ sender: Any?) { zoom(to: EditorWindowZoom.zoomedIn(from: scrollView.magnification)) }
    /// One step down the zoom ladder.
    @objc func zoomOut(_ sender: Any?) { zoom(to: EditorWindowZoom.zoomedOut(from: scrollView.magnification)) }
    @objc func actualSize(_ sender: Any?) { zoom(to: 1) }

    /// Upstream's zoom presets; the menu item's tag is the percentage.
    static var zoomPresets: [Int] { EditorWindowZoom.presetPercents }

    @objc func zoomPreset(_ sender: NSMenuItem) {
        zoom(to: EditorWindowZoom.factor(percent: sender.tag))
    }

    /// The whole image in the window, at most at 100 %.
    @objc func zoomToFit(_ sender: Any?) {
        let viewport = scrollView.contentView.bounds.size.applying(CGAffineTransform(scaleX: scrollView.magnification, y: scrollView.magnification))
        let image = canvas.pointSize
        guard image.width > 0, image.height > 0 else { return }
        setMagnification(min(viewport.width / image.width, viewport.height / image.height, 1))
    }

    /// Zooms out to fit when the image is larger than the window, else shows it at 100 %.
    func zoomToFitIfLarger() {
        let image = canvas.pointSize
        let viewport = scrollView.contentSize
        if image.width > viewport.width || image.height > viewport.height {
            zoomToFit(nil)
        } else {
            setMagnification(1)
        }
    }

    private func clampedMagnification(_ value: CGFloat) -> CGFloat {
        min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
    }

    /// A magnification with the image's middle in the middle (fitting).
    func setMagnification(_ value: CGFloat) {
        scrollView.magnification = clampedMagnification(value)
        center(on: NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        refreshDocumentState()
    }

    /// Zoom by key or menu: zooming in goes to the selection, or keeps a fitting image's top left in view; otherwise
    /// the middle of the view stays (upstream `ZoomSetValue`).
    func zoom(to value: CGFloat) {
        let old = scrollView.magnification
        let new = clampedMagnification(value)
        guard abs(new - old) > 0.0001 else {
            refreshDocumentState()
            return
        }
        let scale = editorDocument.scale
        let selection = canvas.selectedAnnotations.map(\.bounds).reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
            .map { CGRect(x: $0.minX / scale, y: $0.minY / scale, width: $0.width / scale, height: $0.height / scale) }
        let anchor = EditorWindowZoom.anchor(viewport: scrollView.contentView.bounds, imageSize: canvas.bounds.size,
                                             selection: selection, zoomingIn: new > old)
        scrollView.magnification = new
        center(on: anchor)
        refreshDocumentState()
    }

    /// ⌘ and the scroll wheel: one step, and the point under the mouse stays under it (like pinching).
    func wheelZoom(zoomIn: Bool, at point: NSPoint) {
        let old = scrollView.magnification
        let new = clampedMagnification(zoomIn ? EditorWindowZoom.zoomedIn(from: old) : EditorWindowZoom.zoomedOut(from: old))
        guard abs(new - old) > 0.0001 else { return }
        let clip = scrollView.contentView
        let offset = NSPoint(x: point.x - clip.bounds.minX, y: point.y - clip.bounds.minY)
        scrollView.magnification = new
        let ratio = old / new
        scroll(to: NSPoint(x: point.x - offset.x * ratio, y: point.y - offset.y * ratio))
        refreshDocumentState()
    }

    /// Scrolls so `point` of the image is in the middle of the view, as far as the image allows.
    private func center(on point: NSPoint) {
        let size = scrollView.contentView.bounds.size
        scroll(to: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    private func scroll(to origin: NSPoint) {
        let clip = scrollView.contentView
        let proposed = NSRect(origin: origin, size: clip.bounds.size)
        clip.setBoundsOrigin(clip.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// After a pinch the status bar shows the new zoom.
    @objc func liveMagnifyEnded(_ notification: Notification) {
        refreshDocumentState()
    }
}

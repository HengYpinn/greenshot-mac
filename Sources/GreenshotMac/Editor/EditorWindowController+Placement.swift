// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Where the editor window opens and how large it is (upstream `ImageEditorForm` `ApplyStoredPlacement`,
/// `GetOptimalWindowSize`, `SurfaceSizeChanged` and `IEditorConfiguration` `WindowNormalPosition`, `ShowWindowCommand`,
/// `MatchSizeToCapture`). A new editor opens where the last one was closed; with "match size to capture" it is sized
/// to the image from that top left. A place on a screen that is gone is forgotten (upstream BUG-1812).
extension EditorWindowController {
    /// The last editor's frame when it was neither zoomed nor minimised, `NSStringFromRect`.
    private static let frameDefaultsKey = "editorWindowNormalFrame"
    /// Whether the last editor was zoomed (upstream `ShowWindowCommand` Maximize).
    private static let zoomedDefaultsKey = "editorWindowZoomed"
    /// Earlier versions kept a frame descriptor under this key.
    private static let oldFrameDefaultsKey = "editorWindowFrame"

    private static var visibleScreens: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    /// The remembered frame if it is still on a screen; a frame that isn't is forgotten.
    private static func rememberedFrame() -> NSRect? {
        // The snapshots don't depend on (or change) the user's last editor.
        guard Snapshots.requestedFolder == nil else { return nil }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: oldFrameDefaultsKey)
        guard let text = defaults.string(forKey: frameDefaultsKey) else { return nil }
        let frame = NSRectFromString(text)
        guard EditorWindowPlacement.isUsable(frame, screens: visibleScreens) else {
            defaults.removeObject(forKey: frameDefaultsKey)
            defaults.removeObject(forKey: zoomedDefaultsKey)
            return nil
        }
        return frame
    }

    /// Places a new editor window: where the last editor was, sized to the image with "match size to capture"
    /// (else the last editor's size); without a usable remembered place it is centred. Larger images are zoomed to fit.
    func placeWindow() {
        guard let window else { return }
        let remembered = Self.rememberedFrame()
        if let remembered, !settings.value.matchSizeToCapture {
            window.setFrame(remembered, display: false)
        } else {
            let topLeft = remembered.map { NSPoint(x: $0.minX, y: $0.maxY) }
            let screen = remembered.flatMap { EditorWindowPlacement.screen(for: $0, screens: Self.visibleScreens) }
            fitWindowToImage(topLeft: topLeft, screen: screen)
        }
        window.layoutIfNeeded()
        zoomToFitIfLarger()
        normalFrame = window.frame
        fittedImageSize = editorDocument.imageSize
        // Zoomed again once it is on screen (zooming needs the window's screen).
        zoomsWhenShown = remembered != nil && UserDefaults.standard.bool(forKey: Self.zoomedDefaultsKey)
    }

    /// Sizes the window to show the image at 100 % (upstream `GetOptimalWindowSize`): image plus the bars, at least
    /// 650 × 530, at most the screen, from `topLeft` or centred.
    func fitWindowToImage(topLeft: NSPoint?, screen: CGRect?) {
        guard let window else { return }
        window.layoutIfNeeded()
        let chrome = NSSize(width: window.frame.width - scrollView.frame.width,
                            height: window.frame.height - scrollView.frame.height)
        let visible = screen ?? (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let frame = EditorWindowPlacement.fittedFrame(contentSize: canvas.pointSize, chrome: chrome, topLeft: topLeft, screen: visible)
        window.setFrame(frame, display: window.isVisible)
        window.layoutIfNeeded()
    }

    /// A reused editor got a new screenshot: with "match size to capture" it is sized to it, keeping its top left.
    func refitWindowForNewImage() {
        guard let window else { return }
        if settings.value.matchSizeToCapture, !window.isZoomed {
            fitWindowToImage(topLeft: NSPoint(x: window.frame.minX, y: window.frame.maxY), screen: window.screen?.visibleFrame)
        }
        window.layoutIfNeeded()
        zoomToFitIfLarger()
        fittedImageSize = editorDocument.imageSize
    }

    /// After crop, resize, rotate or a larger canvas: with "match size to capture" the window follows the image's size
    /// (upstream `SurfaceSizeChanged`), unless it is zoomed (that would un-zoom it).
    func refitWindowIfImageResized() {
        guard let fitted = fittedImageSize, fitted != editorDocument.imageSize, let window else { return }
        fittedImageSize = editorDocument.imageSize
        guard settings.value.matchSizeToCapture, window.isVisible, !window.isZoomed, !window.inLiveResize else { return }
        fitWindowToImage(topLeft: NSPoint(x: window.frame.minX, y: window.frame.maxY), screen: window.screen?.visibleFrame)
    }

    /// Keeps the frame the window has when it is neither zoomed nor minimised, for the next editor.
    func rememberNormalFrame() {
        guard let window, window.isVisible, !window.isMiniaturized, !isZoomAnimating else { return }
        wasZoomed = window.isZoomed
        if !wasZoomed { normalFrame = window.frame }
    }

    @objc func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if !window.isZoomed { normalFrame = window.frame }
        isZoomAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + window.animationResizeTime(newFrame) + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isZoomAnimating = false
                self.wasZoomed = self.window?.isZoomed ?? false
            }
        }
        return true
    }

    /// Zooms a new window whose remembered editor was zoomed, once it is on screen.
    func restoreZoomIfNeeded() {
        guard zoomsWhenShown, let window else { return }
        zoomsWhenShown = false
        if !window.isZoomed { window.zoom(nil) }
    }

    /// Remembers this window's place for the next editor (upstream stores the placement when the editor closes). Uses
    /// the frame kept while it was visible: when another app is active the editors are hidden.
    func savePlacement() {
        guard let normalFrame, Snapshots.requestedFolder == nil else { return }
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromRect(normalFrame), forKey: Self.frameDefaultsKey)
        defaults.set(wasZoomed, forKey: Self.zoomedDefaultsKey)
    }
}

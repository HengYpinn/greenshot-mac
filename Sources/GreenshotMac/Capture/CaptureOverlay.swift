// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

/// What a click on a QR code's menu on the capture screen asks for.
enum BarcodeAction: Equatable {
    case copy(String)
    case open(URL)
}

/// What the user picked on the capture screen.
struct OverlaySelection {
    /// Quartz global points.
    var rect: CGRect
    var window: WindowInfo?
    /// The text mode: the recognised text of the selected line or words.
    var text: String?
    /// The fixed-size mode: the size (in pixels) that was used.
    var fixedSize: CaptureSize?
    /// Whether the picture with the mouse pointer (M) is to be cropped.
    var includesPointer = false
    /// A QR code's menu was used: nothing is captured.
    var barcodeAction: BarcodeAction?
    var mode: CaptureOverlayController.Mode = .region
}

/// The capture screen (upstream `Greenshot/Capturing/Views/CaptureWindow.xaml.cs`): the frozen picture of every
/// display, where the user selects a region, a window, a fixed size area or text. One borderless window per
/// display; this controller holds the state they share.
///
/// Keys, as in upstream's capture user guide: Space switches region/window mode (from fixed size or text: back to
/// region), F the fixed-size mode, T the text mode, Enter starts and finishes a keyboard selection, the arrow keys
/// move the cursor one pixel (⌃ or ⌘: ten), Shift keeps a drag to one direction, M shows or hides the mouse pointer
/// in the capture, Z the zoomer, H or F1 the keys, I the info, P moves the preview of the selection (corner, at the
/// zoomer, off), D the window details, Esc cancels. In the fixed-size mode 1–9, PgUp/PgDn (or [ and ]) pick the
/// size, C the corner the mouse holds, ⌥ places it without snapping.
@MainActor
final class CaptureOverlayController {
    enum Mode { case region, window, fixedSize, text }
    private enum Axis { case horizontal, vertical }

    private static var active: CaptureOverlayController?

    /// Shows the capture screen and returns the selection, or nil when it was cancelled.
    /// `screens` is the picture without the mouse pointer, `pointerScreens` the one with it (for M).
    static func select(screens: [FrozenScreen], pointerScreens: [FrozenScreen]?, windows: [WindowInfo], mode: Mode,
                       settings: SettingsStore) async -> OverlaySelection? {
        await withCheckedContinuation { continuation in
            let controller = CaptureOverlayController(
                screens: screens, windows: windows, mode: mode, zoomer: settings.value.zoomerEnabled, settings: settings,
                pointerScreens: pointerScreens, pointerVisible: settings.value.captureMousePointer && pointerScreens != nil
            ) {
                continuation.resume(returning: $0)
            }
            active = controller
            controller.show()
        }
    }

    /// The frozen displays as shown now: with or without the mouse pointer.
    var screens: [FrozenScreen] { pointerVisible ? (pointerScreens ?? plainScreens) : plainScreens }
    let plainScreens: [FrozenScreen]
    let pointerScreens: [FrozenScreen]?
    let windows: [WindowInfo]
    let settings: SettingsStore?
    private(set) var mode: Mode
    private(set) var zoomerVisible: Bool
    private(set) var helpVisible: Bool
    private(set) var infoVisible: Bool
    private(set) var previewPlacement: SelectionPreviewPlacement
    private(set) var pointerVisible: Bool
    private(set) var windowDetailsVisible = false
    private(set) var cursor: CGPoint = .zero
    /// Where the selection started (mouse down, or the first Enter).
    private(set) var anchor: CGPoint?
    /// The rectangle that would be captured now, Quartz global points.
    private(set) var selection: CGRect?
    /// The window mode's window.
    private(set) var hoveredWindow: WindowInfo?
    /// The front window under the mouse, in every mode (for the info and for snapping).
    private(set) var windowUnderCursor: WindowInfo?

    // Fixed size
    private(set) var fixedSizes: [FixedSizeEntry]
    private(set) var fixedSizeIndex: Int
    private(set) var fixedAnchor: FixedCaptureAnchor

    // Text and QR codes (CaptureOverlayAnalysis.swift)
    let ocrLanguage: String
    let scanBarcodes: Bool
    /// Recognise the text when the capture screen opens, in every mode (upstream `AlwaysRunOCROnCapture`).
    let recognizesTextAtOnce: Bool
    /// How see-through the zoomer is (upstream `ZoomerOpacity`).
    let zoomerOpacity: CGFloat
    /// The recognised lines in global points; nil until the text mode ran the recognition.
    var textLines: [RecognizedLine]?
    var recognizingText = false
    private(set) var hoveredLine: RecognizedLine?
    /// The QR codes found on the frozen displays, in global points.
    var barcodes: [DetectedBarcode] = []
    private(set) var hoveredBarcode: DetectedBarcode?
    /// The menu of a clicked QR code.
    var barcodeMenu: BarcodeMenu?

    private var shiftStart: CGPoint?
    private var shiftAxis: Axis?
    private var overlayWindows: [OverlayWindow] = []
    private let completion: (OverlaySelection?) -> Void
    private(set) var finished = false
    /// A mode key during a drag: the mouse-up that ends the drag doesn't capture in the new mode.
    private var ignoresMouseUp = false
    private var previewCache: (rect: CGRect, pointer: Bool, image: CGImage, scale: CGFloat)?

    // Movement (CaptureOverlayAnimator.swift). Only while the capture screen is on the screen: the snapshots draw the
    // end state.
    /// The capture screen is on the screen.
    private(set) var isShown = false
    /// Things slide and fade; not with Reduce motion (upstream: not in a remote session).
    private(set) var animates = false
    /// When the selection last changed: the panels avoid it only once it stayed the same for a moment.
    var selectionChangedAt = Date.distantPast
    var settleTimer: Timer?
    /// The window selection sliding from window to window.
    var selectionMotion: CaptureMotion?
    /// When the labels of the window selection started to fade in.
    var labelsAppearedAt: Date?
    /// The next window selection grows out of the mouse.
    var growsFromCursor = false
    lazy var animator = CaptureOverlayAnimator { [weak self] in self?.redraw() }

    init(screens: [FrozenScreen], windows: [WindowInfo], mode: Mode, zoomer: Bool, settings: SettingsStore? = nil,
         pointerScreens: [FrozenScreen]? = nil, pointerVisible: Bool = false,
         completion: @escaping (OverlaySelection?) -> Void) {
        let values = settings?.value ?? AppSettings()
        self.plainScreens = screens
        self.pointerScreens = pointerScreens
        self.pointerVisible = pointerVisible && pointerScreens != nil
        self.windows = windows
        self.settings = settings
        self.mode = mode
        self.zoomerVisible = zoomer
        self.helpVisible = values.captureHelpVisible
        self.infoVisible = values.captureInfoVisible
        self.previewPlacement = SelectionPreviewPlacement(visible: values.captureSelectionPreviewVisible,
                                                          inZoomer: values.zoomerShowsPreview)
        let sizes = FixedSizeCapture.sizes(configured: values.fixedCaptureSizes, recent: values.recentCaptureSizes)
        self.fixedSizes = sizes
        // The mode starts with the size used last time.
        self.fixedSizeIndex = values.fixedCaptureSize.flatMap { size in sizes.firstIndex { $0.size == size } } ?? 0
        self.fixedAnchor = values.fixedCaptureAnchor
        self.ocrLanguage = values.ocrLanguage
        self.scanBarcodes = values.scanQRCodesOnCapture
        self.recognizesTextAtOnce = values.alwaysRunOCROnCapture
        self.zoomerOpacity = CGFloat(min(max(values.zoomerOpacity, 0), 1))
        self.completion = completion
    }

    var desktopBounds: CGRect { ScreenComposer.union(of: screens) }

    func screen(at point: CGPoint) -> FrozenScreen? {
        screens.first { $0.frame.contains(point) }
    }

    /// The display with the mouse, or the nearest one.
    var cursorScreen: FrozenScreen? {
        guard !screens.isEmpty else { return nil }
        return screens[CaptureScreenChoice.screen(at: cursor, frames: screens.map(\.frame))]
    }

    /// The zoomer is for selecting pixels, not whole windows.
    var showsZoomer: Bool { zoomerVisible && mode != .window }

    var currentFixedSize: CaptureSize? {
        fixedSizes.indices.contains(fixedSizeIndex) ? fixedSizes[fixedSizeIndex].size : nil
    }

    private func show() {
        cursor = ScreenSpace.mouseLocation
        for frozen in screens {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == frozen.displayID }) else { continue }
            overlayWindows.append(OverlayWindow(screen: screen, frozen: frozen, controller: self))
        }
        guard !overlayWindows.isEmpty else {
            finish(nil)
            return
        }
        // No NSApp.activate(): since macOS 14 another app may refuse to give up the focus, and activating can switch
        // to the Space of an open editor. The panels show over the current app, even a full screen one, and take
        // the mouse and keys without activating this app.
        isShown = true
        animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        growsFromCursor = mode == .window
        overlayWindows.forEach { $0.orderFrontRegardless() }
        (overlayWindows.first { $0.frozen.frame.contains(cursor) } ?? overlayWindows[0]).makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
        if scanBarcodes { startBarcodeDetection() }
        if mode == .text || recognizesTextAtOnce { startTextRecognition() }
        updateSelection()
    }

    func finish(_ result: OverlaySelection?) {
        guard !finished else { return }
        finished = true
        stopMoving()
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        NSCursor.arrow.set()
        Self.active = nil
        var result = result
        result?.includesPointer = pointerVisible
        completion(result)
    }

    func redraw() {
        overlayWindows.forEach { $0.marksView.needsDisplay = true }
    }

    /// Another window took the keyboard (⌘Tab, a notification, a dialog of another app) while the capture screen stays
    /// on top: the next mouse move gives the keys back, so Esc, Enter and the other keys work again (upstream
    /// `CaptureWindow.xaml.cs` `_lostFocus`). The panels don't activate the app, so neither does this.
    func takeKeysBack(to window: NSWindow) {
        guard !finished, !overlayWindows.contains(where: \.isKeyWindow) else { return }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Mouse

    func mouseMoved(to point: CGPoint) {
        cursor = point
        if barcodeMenu != nil {
            barcodeMenu?.hover(at: point)
            redraw()
            return
        }
        updateSelection()
    }

    func mouseDown(at point: CGPoint) {
        cursor = point
        if barcodeMenu != nil {
            pickBarcodeMenuItem(at: point)
            return
        }
        if mode == .region || mode == .text {
            anchor = point
            shiftStart = nil
            shiftAxis = nil
        }
        updateSelection()
    }

    func mouseDragged(to point: CGPoint, shift: Bool) {
        cursor = point
        guard barcodeMenu == nil else { return }
        if !shift {
            shiftStart = nil
            shiftAxis = nil
        }
        updateSelection(shift: shift)
    }

    func mouseUp(at point: CGPoint) {
        guard barcodeMenu == nil else { return }
        if ignoresMouseUp {
            ignoresMouseUp = false
            return
        }
        switch mode {
        case .region:
            guard let start = anchor else { return }
            // A very small drag counts as a click and captures nothing, so the user can just try again.
            if let rect = selection, rect.width >= 3 || rect.height >= 3, rect.width >= 1, rect.height >= 1 {
                finish(OverlaySelection(rect: rect, window: nil))
            } else {
                anchor = nil
                // A click on a QR code opens its menu.
                if let barcode = barcodes.first(where: { $0.bounds.contains(start) }) {
                    openBarcodeMenu(for: barcode, at: point)
                }
                updateSelection()
            }
        case .text:
            finishText(clickedAt: point)
        case .window:
            acceptWindow()
        case .fixedSize:
            acceptFixedSize()
        }
    }

    // MARK: Keys

    func keyDown(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        if barcodeMenu != nil {
            if keyCode == kVK_Escape {
                barcodeMenu = nil
                updateSelection()
            }
            return
        }
        switch keyCode {
        case kVK_Escape:
            finish(nil)
        case kVK_Space:
            switchMode(to: mode == .region ? .window : .region)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            enter()
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            let flags = event.modifierFlags
            moveCursor(keyCode: keyCode, fast: flags.contains(.control) || flags.contains(.command))
        case kVK_F1:
            toggleHelp()
        case kVK_PageUp:
            stepFixedSize(by: -1)
        case kVK_PageDown:
            stepFixedSize(by: 1)
        default:
            if mode == .fixedSize, let index = Self.digitIndex(keyCode: keyCode) {
                pickFixedSize(index)
                return
            }
            letterKey(event.charactersIgnoringModifiers?.lowercased() ?? "")
        }
    }

    private func letterKey(_ key: String) {
        switch key {
        case "z":
            zoomerVisible.toggle()
            let visible = zoomerVisible
            settings?.update { $0.zoomerEnabled = visible }
            redraw()
        case "h": toggleHelp()
        case "i":
            infoVisible.toggle()
            let visible = infoVisible
            settings?.update { $0.captureInfoVisible = visible }
            redraw()
        case "p": nextPreviewPlacement()
        case "m": togglePointer()
        case "f": switchMode(to: .fixedSize)
        case "t": switchMode(to: .text)
        case "d":
            guard mode == .window else { return }
            windowDetailsVisible.toggle()
            redraw()
        case "c":
            guard mode == .fixedSize else { return }
            fixedAnchor = fixedAnchor.next
            let anchor = fixedAnchor
            settings?.update { $0.fixedCaptureAnchor = anchor }
            updateSelection()
        case "[": stepFixedSize(by: -1)
        case "]": stepFixedSize(by: 1)
        default: break
        }
    }

    /// 0 for the 1 key, … 8 for the 9 key (also on the keypad).
    private static func digitIndex(keyCode: Int) -> Int? {
        let row = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let pad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                   kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        return row.firstIndex(of: keyCode) ?? pad.firstIndex(of: keyCode)
    }

    private func toggleHelp() {
        helpVisible.toggle()
        let visible = helpVisible
        settings?.update { $0.captureHelpVisible = visible }
        redraw()
    }

    /// P: in a corner, in the place of the zoomer, off. The placement is remembered (upstream
    /// `CaptureSelectionPreviewVisible` and `ZoomerShowsPreview`).
    private func nextPreviewPlacement() {
        previewPlacement = previewPlacement.next
        let placement = previewPlacement
        settings?.update {
            $0.captureSelectionPreviewVisible = placement.isVisible
            $0.zoomerShowsPreview = placement.isInZoomer
        }
        redraw()
    }

    /// M: the picture with or without the mouse pointer, for this capture only.
    private func togglePointer() {
        guard pointerScreens != nil else {
            NSSound.beep()
            return
        }
        pointerVisible.toggle()
        previewCache = nil
        let shown = screens
        for window in overlayWindows {
            if let frozen = shown.first(where: { $0.displayID == window.frozen.displayID }) { window.show(frozen) }
        }
        redraw()
    }

    func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        modeWillChange(from: mode, to: newMode)
        mode = newMode
        anchor = nil
        shiftStart = nil
        shiftAxis = nil
        windowDetailsVisible = false
        ignoresMouseUp = NSEvent.pressedMouseButtons & 1 != 0
        if mode == .text { startTextRecognition() }
        updateSelection()
    }

    private func enter() {
        switch mode {
        case .region, .text:
            if let anchor {
                let rect = dragRect(from: anchor, to: cursor)
                guard rect.width >= 1, rect.height >= 1 else { return }
                if mode == .region {
                    finish(OverlaySelection(rect: rect, window: nil))
                } else {
                    finishText(in: rect)
                }
            } else {
                anchor = cursor
                updateSelection()
            }
        case .window:
            acceptWindow()
        case .fixedSize:
            acceptFixedSize()
        }
    }

    func shiftChanged(_ down: Bool) {
        if !down {
            shiftStart = nil
            shiftAxis = nil
        }
        // ⌥ switches the snapping of the fixed-size mode.
        updateSelection(shift: down)
    }

    /// Moves the mouse one pixel of the display under it.
    private func moveCursor(keyCode: Int, fast: Bool) {
        let step = (fast ? 10 : 1) / (screen(at: cursor)?.scale ?? 1)
        var point = cursor
        switch keyCode {
        case kVK_LeftArrow: point.x -= step
        case kVK_RightArrow: point.x += step
        case kVK_UpArrow: point.y -= step
        default: point.y += step
        }
        let bounds = desktopBounds
        point.x = min(max(point.x, bounds.minX), bounds.maxX - 0.5)
        point.y = min(max(point.y, bounds.minY), bounds.maxY - 0.5)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        mouseMoved(to: point)
    }

    // MARK: Selection

    private func updateSelection(shift: Bool = false) {
        let previous = selection
        defer { if selection != previous { selectionDidChange(from: previous) } }
        windowUnderCursor = windows.first { $0.frame.contains(cursor) }
        hoveredLine = nil
        hoveredWindow = nil
        switch mode {
        case .region, .text:
            if let anchor {
                selection = dragRect(from: anchor, to: shift ? lockedToAxis(cursor) : cursor)
            } else {
                selection = nil
                if mode == .text { hoveredLine = TextCaptureSelection.line(at: cursor, in: textLines ?? []) }
            }
        case .window:
            hoveredWindow = windowUnderCursor
            if let window = hoveredWindow {
                let visible = window.frame.intersection(desktopBounds)
                selection = visible.isEmpty ? nil : visible
            } else {
                // Over the desktop: the display under the mouse.
                selection = screen(at: cursor)?.frame
            }
        case .fixedSize:
            selection = fixedSelection()
        }
        hoveredBarcode = mode == .region && anchor == nil ? barcodes.first { $0.bounds.contains(cursor) } : nil
        redraw()
    }

    /// The rectangle of a drag: the pixels under both corners belong to it, on the pixel grid of the display with the
    /// mouse, so its size label is exactly the size of the capture (upstream `RegionCaptureTool`, UG "Region").
    private func dragRect(from anchor: CGPoint, to point: CGPoint) -> CGRect {
        CaptureSelection.rect(from: anchor, to: point, scale: cursorScreen?.scale ?? 1)
    }

    /// While Shift is held, the first move decides whether only the width or only the height changes.
    private func lockedToAxis(_ point: CGPoint) -> CGPoint {
        guard let start = shiftStart else {
            shiftStart = point
            return point
        }
        if shiftAxis == nil {
            let dx = abs(point.x - start.x)
            let dy = abs(point.y - start.y)
            if max(dx, dy) >= 2 { shiftAxis = dx >= dy ? .horizontal : .vertical }
        }
        switch shiftAxis {
        case .horizontal: return CGPoint(x: point.x, y: start.y)
        case .vertical: return CGPoint(x: start.x, y: point.y)
        case nil: return start
        }
    }

    /// Drops a started selection (a click that selected nothing), so the user can try again.
    func cancelSelection() {
        anchor = nil
        updateSelection()
    }

    private func acceptWindow() {
        guard let rect = selection else { return }
        finish(OverlaySelection(rect: rect, window: hoveredWindow, mode: .window))
    }

    // MARK: Fixed size

    /// The fixed-size rectangle at the mouse; its edges snap to the window under the mouse and the display unless ⌥ is held.
    private func fixedSelection() -> CGRect? {
        guard let size = currentFixedSize, let monitor = cursorScreen else { return nil }
        let snapping = !NSEvent.modifierFlags.contains(.option)
        let rect = FixedSizeCapture.selection(cursor: cursor, size: size, anchor: fixedAnchor, scale: monitor.scale,
                                              monitor: monitor.frame, desktop: desktopBounds,
                                              snapTargets: windowUnderCursor.map { [$0.frame] } ?? [], snapping: snapping)
        return rect.isEmpty ? nil : rect
    }

    private func pickFixedSize(_ index: Int) {
        guard mode == .fixedSize, fixedSizes.indices.contains(index) else { return }
        fixedSizeIndex = index
        updateSelection()
    }

    private func stepFixedSize(by change: Int) {
        guard mode == .fixedSize else { return }
        pickFixedSize(FixedSizeCapture.step(fixedSizeIndex, by: change, count: fixedSizes.count))
    }

    private func acceptFixedSize() {
        guard let rect = selection, let size = currentFixedSize else { return }
        finish(OverlaySelection(rect: rect, window: nil, fixedSize: size, mode: .fixedSize))
    }

    // MARK: Preview

    /// The picture of the selection for the preview, and its pixels per point; cached while the selection stays.
    func previewImage() -> (image: CGImage, scale: CGFloat)? {
        guard let rect = selection, rect.width >= 1, rect.height >= 1 else { return nil }
        if let cache = previewCache, cache.rect == rect, cache.pointer == pointerVisible { return (cache.image, cache.scale) }
        guard let result = ScreenComposer.image(of: rect, from: screens) else { return nil }
        previewCache = (rect, pointerVisible, result.image, result.scale)
        return result
    }
}

/// One display's part of the capture screen. A non-activating panel: macOS lets those float over every app,
/// including one in full screen, also while an editor window makes this a regular (Dock) app.
final class OverlayWindow: NSPanel {
    private(set) var frozen: FrozenScreen
    let marksView: OverlayMarksView
    private let imageView: FrozenImageView

    @MainActor
    init(screen: NSScreen, frozen: FrozenScreen, controller: CaptureOverlayController) {
        self.frozen = frozen
        let size = screen.frame.size
        marksView = OverlayMarksView(frame: NSRect(origin: .zero, size: size), frozen: frozen, controller: controller)
        imageView = FrozenImageView(frame: NSRect(origin: .zero, size: size), image: frozen.image, scale: frozen.scale)
        // .nonactivatingPanel has to be set here: changing it after init doesn't take effect.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        imageView.autoresizingMask = [.width, .height]
        marksView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        container.addSubview(marksView)
        contentView = container
        initialFirstResponder = marksView
        makeFirstResponder(marksView)
    }

    /// Shows the other picture of this display (with or without the mouse pointer).
    @MainActor
    func show(_ frozen: FrozenScreen) {
        self.frozen = frozen
        marksView.frozen = frozen
        imageView.layer?.contents = frozen.image
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the frozen picture through Core Animation, so redrawing the marks on top stays cheap.
final class FrozenImageView: NSView {
    init(frame: NSRect, image: CGImage, scale: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.contentsScale = scale
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}

/// Passes the input of one display on to the controller and draws its marks (CaptureOverlayDrawing.swift):
/// the selection, labels, crosshair, zoomer, the panels and the text lines and QR codes.
final class OverlayMarksView: NSView {
    var frozen: FrozenScreen
    weak var controller: CaptureOverlayController?
    let accent = NSColor(srgbRed: 0.42, green: 0.75, blue: 0.27, alpha: 1)
    /// Where each panel is now (local points), so panels stay put while they can.
    var panelFrames: [String: CGRect] = [:]
    /// The zoomer's offset from the mouse.
    var zoomerOffset: CGPoint?
    // The panels' movement (CaptureOverlayAnimator.swift).
    var panelMotions: [String: CaptureMotion] = [:]
    var panelAppearedAt: [String: Date] = [:]
    /// The size of each panel while it is shown: it only grows.
    var panelSizes: [String: CGSize] = [:]
    /// The panels of the last drawing, where they were drawn.
    var drawnPanels: [String: (panel: OverlayPanel, frame: CGRect)] = [:]
    /// Panels that were hidden, fading out.
    var fadingPanels: [String: (panel: OverlayPanel, frame: CGRect, start: Date)] = [:]

    init(frame: NSRect, frozen: FrozenScreen, controller: CaptureOverlayController) {
        self.frozen = frozen
        self.controller = controller
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    private func global(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: frozen.frame.minX + p.x, y: frozen.frame.minY + p.y)
    }

    func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frozen.frame.minX, dy: -frozen.frame.minY)
    }

    func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frozen.frame.minX, y: point.y - frozen.frame.minY)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        if let window { controller?.takeKeysBack(to: window) }
        controller?.mouseMoved(to: global(event))
    }

    override func mouseDown(with event: NSEvent) { controller?.mouseDown(at: global(event)) }
    override func mouseDragged(with event: NSEvent) {
        controller?.mouseDragged(to: global(event), shift: event.modifierFlags.contains(.shift))
    }
    override func mouseUp(with event: NSEvent) { controller?.mouseUp(at: global(event)) }
    override func rightMouseDown(with event: NSEvent) { controller?.finish(nil) }
    override func keyDown(with event: NSEvent) { controller?.keyDown(event) }
    override func flagsChanged(with event: NSEvent) { controller?.shiftChanged(event.modifierFlags.contains(.shift)) }

    override func draw(_ dirtyRect: NSRect) {
        drawMarks()
    }
}

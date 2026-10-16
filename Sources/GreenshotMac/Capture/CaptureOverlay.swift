// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

/// What the user picked on the capture screen.
struct OverlaySelection {
    /// Quartz global points.
    var rect: CGRect
    var window: WindowInfo?
}

/// The capture screen (upstream `CaptureWindow`): the frozen picture of every display, where the user selects
/// a region or a window. One borderless window per display; this controller holds the state they share.
///
/// Keys, as in upstream's capture user guide: Space switches region/window mode, Enter starts and finishes
/// a keyboard selection, the arrow keys move the cursor one pixel (⌃ or ⌘: ten), Shift keeps a drag to one
/// direction, Z shows or hides the zoomer, H or F1 the help, Esc cancels.
@MainActor
final class CaptureOverlayController {
    enum Mode { case region, window }
    private enum Axis { case horizontal, vertical }

    private static var active: CaptureOverlayController?

    /// Shows the capture screen and returns the selection, or nil when it was cancelled.
    static func select(screens: [FrozenScreen], windows: [WindowInfo], mode: Mode, zoomer: Bool) async -> OverlaySelection? {
        await withCheckedContinuation { continuation in
            let controller = CaptureOverlayController(screens: screens, windows: windows, mode: mode, zoomer: zoomer) {
                continuation.resume(returning: $0)
            }
            active = controller
            controller.show()
        }
    }

    let screens: [FrozenScreen]
    let windows: [WindowInfo]
    private(set) var mode: Mode
    private(set) var zoomerVisible: Bool
    private(set) var helpVisible = true
    private(set) var cursor: CGPoint = .zero
    /// Where the selection started (mouse down, or the first Enter).
    private(set) var anchor: CGPoint?
    /// The rectangle that would be captured now, Quartz global points.
    private(set) var selection: CGRect?
    private(set) var hoveredWindow: WindowInfo?
    private var shiftStart: CGPoint?
    private var shiftAxis: Axis?
    private var overlayWindows: [OverlayWindow] = []
    private let completion: (OverlaySelection?) -> Void
    private var finished = false

    init(screens: [FrozenScreen], windows: [WindowInfo], mode: Mode, zoomer: Bool,
                 completion: @escaping (OverlaySelection?) -> Void) {
        self.screens = screens
        self.windows = windows
        self.mode = mode
        self.zoomerVisible = zoomer
        self.completion = completion
    }

    var desktopBounds: CGRect { ScreenComposer.union(of: screens) }

    func screen(at point: CGPoint) -> FrozenScreen? {
        screens.first { $0.frame.contains(point) }
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
        overlayWindows.forEach { $0.orderFrontRegardless() }
        (overlayWindows.first { $0.frozen.frame.contains(cursor) } ?? overlayWindows[0]).makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
        updateSelection()
    }

    func finish(_ result: OverlaySelection?) {
        guard !finished else { return }
        finished = true
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        NSCursor.arrow.set()
        Self.active = nil
        completion(result)
    }

    private func redraw() {
        overlayWindows.forEach { $0.marksView.needsDisplay = true }
    }

    // MARK: Mouse

    func mouseMoved(to point: CGPoint) {
        cursor = point
        updateSelection()
    }

    func mouseDown(at point: CGPoint) {
        cursor = point
        if mode == .region {
            anchor = point
            shiftStart = nil
            shiftAxis = nil
        }
        updateSelection()
    }

    func mouseDragged(to point: CGPoint, shift: Bool) {
        cursor = point
        if !shift {
            shiftStart = nil
            shiftAxis = nil
        }
        updateSelection(shift: shift)
    }

    func mouseUp(at point: CGPoint) {
        switch mode {
        case .region:
            guard anchor != nil else { return }
            // A very small drag counts as a click and captures nothing, so the user can just try again.
            if let rect = selection, rect.width >= 3 || rect.height >= 3, rect.width >= 1, rect.height >= 1 {
                finish(OverlaySelection(rect: rect, window: nil))
            } else {
                anchor = nil
                updateSelection()
            }
        case .window:
            acceptWindow()
        }
    }

    // MARK: Keys

    func keyDown(_ event: NSEvent) {
        let flags = event.modifierFlags
        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(nil)
        case kVK_Space:
            mode = mode == .region ? .window : .region
            anchor = nil
            updateSelection()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            switch mode {
            case .region:
                if let anchor {
                    let rect = Geometry.rect(from: anchor, to: cursor)
                    if rect.width >= 1, rect.height >= 1 { finish(OverlaySelection(rect: rect, window: nil)) }
                } else {
                    anchor = cursor
                    updateSelection()
                }
            case .window:
                acceptWindow()
            }
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            moveCursor(keyCode: Int(event.keyCode), fast: flags.contains(.control) || flags.contains(.command))
        case kVK_F1:
            helpVisible.toggle()
            redraw()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                zoomerVisible.toggle()
                redraw()
            case "h":
                helpVisible.toggle()
                redraw()
            default:
                break
            }
        }
    }

    func shiftChanged(_ down: Bool) {
        if !down {
            shiftStart = nil
            shiftAxis = nil
            updateSelection()
        }
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
        switch mode {
        case .region:
            hoveredWindow = nil
            if let anchor {
                selection = Geometry.rect(from: anchor, to: shift ? lockedToAxis(cursor) : cursor)
            } else {
                selection = nil
            }
        case .window:
            hoveredWindow = windows.first { $0.frame.contains(cursor) }
            if let window = hoveredWindow {
                let visible = window.frame.intersection(desktopBounds)
                selection = visible.isEmpty ? nil : visible
            } else {
                // Over the desktop: the display under the mouse.
                selection = screen(at: cursor)?.frame
            }
        }
        redraw()
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

    private func acceptWindow() {
        guard let rect = selection else { return }
        finish(OverlaySelection(rect: rect, window: hoveredWindow))
    }
}

/// One display's part of the capture screen. A non-activating panel: macOS lets those float over every app,
/// including one in full screen, also while an editor window makes this a regular (Dock) app.
final class OverlayWindow: NSPanel {
    let frozen: FrozenScreen
    let marksView: OverlayMarksView

    @MainActor
    init(screen: NSScreen, frozen: FrozenScreen, controller: CaptureOverlayController) {
        self.frozen = frozen
        let size = screen.frame.size
        marksView = OverlayMarksView(frame: NSRect(origin: .zero, size: size), frozen: frozen, controller: controller)
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
        let imageView = FrozenImageView(frame: container.bounds, image: frozen.image, scale: frozen.scale)
        imageView.autoresizingMask = [.width, .height]
        marksView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        container.addSubview(marksView)
        contentView = container
        initialFirstResponder = marksView
        makeFirstResponder(marksView)
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

/// Draws the selection, labels, crosshair, zoomer and help on one display, and passes the input on.
final class OverlayMarksView: NSView {
    private let frozen: FrozenScreen
    private weak var controller: CaptureOverlayController?
    private let accent = NSColor(srgbRed: 0.42, green: 0.75, blue: 0.27, alpha: 1)

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

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frozen.frame.minX, dy: -frozen.frame.minY)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let context = NSGraphicsContext.current?.cgContext else { return }
        let cursor = CGPoint(x: controller.cursor.x - frozen.frame.minX, y: controller.cursor.y - frozen.frame.minY)
        let cursorHere = bounds.contains(cursor)
        let selection = controller.selection.map(local)

        // Dim everything outside the selection a little, so the capture screen is recognizable.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let selection { dim.addRect(selection) }
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(selection == nil ? 0.12 : 0.35).cgColor)
        context.fillPath(using: .evenOdd)

        if let selection, selection.intersects(bounds) {
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: 0.5, dy: 0.5))
            drawSizeLabel(for: selection, in: context)
        }

        if controller.mode == .region && controller.anchor == nil && cursorHere {
            context.setStrokeColor(accent.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 0, y: cursor.y.rounded() + 0.5))
            context.addLine(to: CGPoint(x: bounds.maxX, y: cursor.y.rounded() + 0.5))
            context.move(to: CGPoint(x: cursor.x.rounded() + 0.5, y: 0))
            context.addLine(to: CGPoint(x: cursor.x.rounded() + 0.5, y: bounds.maxY))
            context.strokePath()
        }

        if controller.mode == .region && controller.zoomerVisible && cursorHere {
            drawZoomer(at: cursor, in: context)
        }
        if controller.helpVisible && cursorHere {
            drawHelp(avoiding: cursor, selection: selection)
        }
    }

    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white,
        ])
    }

    private func drawBubble(_ text: NSAttributedString, at origin: CGPoint) -> CGRect {
        let size = text.size()
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
        return box
    }

    /// The size of the selection in pixels, and the window title in window mode.
    private func drawSizeLabel(for selection: CGRect, in context: CGContext) {
        guard let controller else { return }
        let width = Int((selection.width * frozen.scale).rounded())
        let height = Int((selection.height * frozen.scale).rounded())
        var text = "\(width) × \(height)"
        if controller.mode == .window, let window = controller.hoveredWindow {
            text = "\(window.menuTitle)   \(text)"
        }
        let string = label(text)
        let size = string.size()
        var origin = CGPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + size.height + 8 > bounds.maxY { origin.y = selection.maxY - size.height - 12 }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 16)
        origin.y = max(origin.y, 4)
        _ = drawBubble(string, at: origin)
    }

    /// The magnifier next to the mouse: 8 points per pixel of the frozen picture, the pixel under the mouse framed.
    private func drawZoomer(at cursor: CGPoint, in context: CGContext) {
        let diameter: CGFloat = 128
        let magnification: CGFloat = 8
        let pixelsAcross = (diameter / magnification).rounded(.down)
        let scale = frozen.scale
        let pixel = CGPoint(x: (cursor.x * scale).rounded(.down), y: (cursor.y * scale).rounded(.down))
        let source = CGRect(x: pixel.x - (pixelsAcross / 2).rounded(.down), y: pixel.y - (pixelsAcross / 2).rounded(.down),
                            width: pixelsAcross, height: pixelsAcross)

        var zoom = CGRect(x: cursor.x + 24, y: cursor.y + 24, width: diameter, height: diameter)
        if zoom.maxX > bounds.maxX - 8 { zoom.origin.x = cursor.x - 24 - diameter }
        if zoom.maxY > bounds.maxY - 30 { zoom.origin.y = cursor.y - 24 - diameter }

        // Where the source square lands, so that the pixel under the mouse sits in the middle.
        let destinationOrigin = CGPoint(x: zoom.midX - (pixel.x - source.minX + 0.5) * magnification,
                                        y: zoom.midY - (pixel.y - source.minY + 0.5) * magnification)
        let imageBounds = CGRect(x: 0, y: 0, width: frozen.image.width, height: frozen.image.height)
        let visible = source.intersection(imageBounds)

        context.saveGState()
        context.addEllipse(in: zoom)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(zoom)
        if !visible.isEmpty, let crop = frozen.image.cropping(to: visible) {
            let destination = CGRect(x: destinationOrigin.x + (visible.minX - source.minX) * magnification,
                                     y: destinationOrigin.y + (visible.minY - source.minY) * magnification,
                                     width: visible.width * magnification, height: visible.height * magnification)
            NSImage(cgImage: crop, size: destination.size)
                .draw(in: destination, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        }
        let center = CGRect(x: destinationOrigin.x + (pixel.x - source.minX) * magnification,
                            y: destinationOrigin.y + (pixel.y - source.minY) * magnification,
                            width: magnification, height: magnification)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1)
        context.stroke(center.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: zoom.insetBy(dx: 1, dy: 1))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: zoom.insetBy(dx: -0.5, dy: -0.5))

        let coordinates = label("\(Int(pixel.x)), \(Int(pixel.y))", size: 11)
        let size = coordinates.size()
        _ = drawBubble(coordinates, at: CGPoint(x: zoom.midX - size.width / 2 - 6, y: zoom.maxY + 4))
    }

    private static let helpLines = [
        ("Drag", "select a region"),
        ("Space", "switch between region and window"),
        ("Enter", "start and finish a selection with the keys"),
        ("← → ↑ ↓", "move one pixel, with ⌃ ten"),
        ("Shift", "keep a drag to one direction"),
        ("Z", "zoomer on or off"),
        ("H", "hide this help"),
        ("Esc", "cancel"),
    ]

    /// The keys, in the first corner that is free of the mouse and the selection; hidden when none is.
    private func drawHelp(avoiding cursor: CGPoint, selection: CGRect?) {
        let keyFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textFont = NSFont.systemFont(ofSize: 12)
        let keyWidth = Self.helpLines.map { NSAttributedString(string: $0.0, attributes: [.font: keyFont]).size().width }.max() ?? 0
        let textWidth = Self.helpLines.map { NSAttributedString(string: $0.1, attributes: [.font: textFont]).size().width }.max() ?? 0
        let lineHeight: CGFloat = 18
        let size = CGSize(width: keyWidth + textWidth + 40, height: CGFloat(Self.helpLines.count) * lineHeight + 20)
        let corners = [CGPoint(x: 20, y: 20), CGPoint(x: bounds.maxX - size.width - 20, y: 20),
                       CGPoint(x: 20, y: bounds.maxY - size.height - 20),
                       CGPoint(x: bounds.maxX - size.width - 20, y: bounds.maxY - size.height - 20)]
        let free = corners.map { CGRect(origin: $0, size: size) }.first { box in
            !box.insetBy(dx: -40, dy: -40).contains(cursor) && !(selection.map { box.intersects($0) } ?? false)
        }
        guard let box = free else { return }

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        for (index, line) in Self.helpLines.enumerated() {
            let y = box.minY + 10 + CGFloat(index) * lineHeight
            NSAttributedString(string: line.0, attributes: [.font: keyFont, .foregroundColor: accent])
                .draw(at: CGPoint(x: box.minX + 12, y: y))
            NSAttributedString(string: line.1, attributes: [.font: textFont, .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: box.minX + 24 + keyWidth, y: y))
        }
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import UniformTypeIdentifiers

/// The drawing surface of the editor (upstream `Surface`). The view is sized in points; the document works in
/// image pixels, so a Retina capture shows at its real size.
@MainActor
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation, @preconcurrency NSTextInputClient {
    let document: EditorDocument
    /// The style new elements of a kind get (the last used one).
    var styleProvider: (AnnotationKind) -> AnnotationStyle = { .defaults(for: $0) }
    /// The emoji new emoji elements get.
    var emojiProvider: () -> String = { "🙂" }
    /// An emoji was picked from the canvas's menu, for the selected emoji element.
    var onPickEmoji: ((String) -> Void)?
    var onDocumentChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onToolChange: (() -> Void)?
    var onCopy: (() -> Void)?

    var tool: EditorTool = .select {
        didSet {
            guard oldValue != tool else { return }
            commitEditing()
            if case .crop = drag { drag = nil }
            if case .rubberBand = drag {
                drag = nil
                rubberBand = nil
            }
            if oldValue == .crop || tool == .crop { cropRect = nil }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            onToolChange?()
            if tool == .crop && cropMode == .auto {
                // Upstream `BtnCropClick` → `InitCropMode`: the crop tool in its Auto mode crops at once.
                DispatchQueue.main.async { [weak self] in self?.runAutoCrop() }
            }
        }
    }

    /// The selected elements, in the order they were selected; the last one is the primary one, whose properties
    /// the property bar shows (upstream selects several with Shift-click or Select All).
    private(set) var selectedIDs: [UUID] = [] {
        didSet {
            guard oldValue != selectedIDs else { return }
            needsDisplay = true
            onSelectionChange?()
            NotificationCenter.default.post(name: .canvasSelectionDidChange, object: self)
        }
    }

    /// The primary selected element.
    var selectedID: UUID? { selectedIDs.last }
    private var selectedSet: Set<UUID> { Set(selectedIDs) }

    /// The crop rectangle being drawn, image pixels.
    private(set) var cropRect: CGRect? {
        didSet {
            needsDisplay = true
            onToolChange?()
        }
    }
    /// The crop tool's mode; C cycles it while cropping (upstream `CycleCropMode`).
    private(set) var cropMode: CropMode = .crop {
        didSet { needsDisplay = true; onToolChange?() }
    }

    /// Chooses a crop mode (the crop bar's buttons; upstream `SelectCropMode`): another mode drops the drawn area,
    /// Auto crops at once (within the drawn area, if there is one).
    func selectCropMode(_ mode: CropMode) {
        guard mode != cropMode || mode == .auto else { return }
        cropMode = mode
        if mode == .auto {
            runAutoCrop()
        } else {
            cropRect = nil
        }
    }

    /// Upstream `CycleCropMode`: Crop, Crop Out Vertically, Crop Out Horizontally, Auto Crop, and round again.
    func cycleCropMode() {
        let modes = CropMode.allCases
        let index = modes.firstIndex(of: cropMode) ?? 0
        selectCropMode(modes[(index + 1) % modes.count])
    }

    /// Upstream `InitCropMode(AutoCrop)`: auto crops with the editor window's Auto Crop; when that isn't possible the
    /// crop tool stays, back in its Crop mode.
    private func runAutoCrop() {
        guard tool == .crop, cropMode == .auto, let controller = editorWindowController else { return }
        controller.autoCrop(nil)
        if tool == .crop {
            cropMode = .crop
            cropRect = nil
        }
    }

    /// Shows a crop area as if it was drawn, for the snapshots.
    func showCropArea(_ rect: CGRect?) {
        cropRect = rect
    }

    /// The editor window the canvas is in: its settings, and the image operations the crop modes and the Z key use.
    private var editorWindowController: EditorWindowController? {
        window?.windowController as? EditorWindowController
    }

    /// The app settings (the defaults when the canvas is not in an editor window).
    private var appSettings: AppSettings {
        editorWindowController?.settings.value ?? AppSettings()
    }

    private enum Drag {
        case create(id: UUID, origin: CGPoint)
        case move(originals: [Annotation], origin: CGPoint)
        case resize(original: Annotation, handle: Handle)
        case crop(origin: CGPoint)
        /// A handle of the crop area being dragged.
        case cropResize(original: CGRect, handle: Handle)
        /// A rubber band drawn on empty canvas with the Select tool; `kept` are the elements selected before, which
        /// stay selected with Shift or Command.
        case rubberBand(origin: CGPoint, kept: [UUID])
    }

    private var drag: Drag?
    /// How far apart the points of the freehand drawing being drawn are at least, image pixels.
    private var freehandSpacing: CGFloat = 6
    /// The rubber band being drawn, image pixels.
    private var rubberBand: CGRect? {
        didSet { needsDisplay = true }
    }
    private var rendered: CGImage?
    private var textView: AlignedTextView?
    private var editingID: UUID?
    /// The typing undo of one text editing session, thrown away when it ends (not left on the window's manager).
    private var textUndoManager: UndoManager?

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        setFrameSize(pointSize)
        // Image files, pictures and links to pictures dropped on the canvas become image elements.
        registerForDraggedTypes([.fileURL, .URL, .string] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) })
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var pointSize: NSSize {
        NSSize(width: document.imageSize.width / document.scale, height: document.imageSize.height / document.scale)
    }

    var selectedAnnotation: Annotation? { selectedID.flatMap(document.annotation) }
    /// All selected elements, back to front.
    var selectedAnnotations: [Annotation] { document.annotations(selectedSet) }
    var isEditingText: Bool { textView != nil }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    /// Image pixels per point on screen: handle sizes and click tolerance stay the same at every zoom.
    private var pixelsPerScreenPoint: CGFloat { document.scale / magnification }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * document.scale, y: p.y * document.scale)
    }

    private func viewRect(_ r: CGRect) -> CGRect {
        let s = document.scale
        return CGRect(x: r.minX / s, y: r.minY / s, width: r.width / s, height: r.height / s)
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / document.scale, y: p.y / document.scale)
    }

    /// Call after every change of the document.
    func documentChanged() {
        rendered = nil
        if frame.size != pointSize { setFrameSize(pointSize) }
        let remaining = selectedIDs.filter { document.annotation($0) != nil }
        if remaining != selectedIDs { selectedIDs = remaining }
        needsDisplay = true
        onDocumentChange?()
    }

    func select(_ id: UUID?) {
        selectedIDs = id.map { [$0] } ?? []
    }

    func select(_ ids: [UUID]) {
        selectedIDs = ids
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if rendered == nil {
            rendered = AnnotationRenderer.flatten(base: document.baseImage, annotations: document.annotations,
                                                  scale: document.scale, hiding: editingID, counterStart: document.counterStart)
        }
        if let rendered {
            context.saveGState()
            context.interpolationQuality = magnification >= 2 ? .none : .high
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(rendered, in: CGRect(origin: .zero, size: bounds.size))
            context.restoreGState()
        }
        drawSelection(in: context)
        drawCrop(in: context)
        drawRubberBand(in: context)
    }

    /// The rubber band of the Select tool: a dashed frame, lightly filled.
    private func drawRubberBand(in context: CGContext) {
        guard let band = rubberBand else { return }
        let rect = viewRect(band)
        let line = 1 / magnification
        context.saveGState()
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        context.fill(rect)
        context.setLineWidth(line)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineDash(phase: 0, lengths: [4 * line, 3 * line])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawSelection(in context: CGContext) {
        let line = 1 / magnification
        let accent = NSColor.controlAccentColor.cgColor
        if selectedIDs.count > 1 {
            // Several selected: a frame around each, no handles (upstream shows the grippers of one element only).
            context.saveGState()
            context.setLineWidth(line)
            context.setStrokeColor(accent)
            context.setLineDash(phase: 0, lengths: [4 * line, 3 * line])
            for a in selectedAnnotations {
                context.stroke(viewRect(a.bounds).insetBy(dx: -3 * line, dy: -3 * line))
            }
            context.restoreGState()
            return
        }
        guard let a = selectedAnnotation, a.id != editingID else { return }
        context.saveGState()
        if a.kind.isBoxShaped || a.kind == .freehand {
            context.setLineWidth(line)
            context.setStrokeColor(accent)
            context.setLineDash(phase: 0, lengths: [4 * line, 3 * line])
            context.stroke(viewRect(a.bounds).insetBy(dx: -3 * line, dy: -3 * line))
            context.setLineDash(phase: 0, lengths: [])
        }
        let size = 8 * line
        for handle in Handle.handles(for: a) {
            let p = viewPoint(handle.position(in: a))
            let box = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.setStrokeColor(accent)
            context.setLineWidth(line)
            context.stroke(box)
        }
        context.restoreGState()
    }

    /// The crop area: what goes is shaded, outside it when cropping, inside it when cutting rows or columns out
    /// (upstream `CropContainer.Draw`), with its handles and a hint.
    private func drawCrop(in context: CGContext) {
        guard tool == .crop, let crop = cropRect else { return }
        let rect = viewRect(crop)
        let line = 1 / magnification
        let cutsOut = cropMode == .vertical || cropMode == .horizontal
        context.saveGState()
        if cutsOut {
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.fill(rect)
        } else {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(rect)
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.fillPath(using: .evenOdd)
        }
        context.setLineWidth(line)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineDash(phase: 0, lengths: [5 * line, 4 * line])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
        let size = 8 * line
        let box = Annotation(kind: .rectangle, start: crop.origin, end: CGPoint(x: crop.maxX, y: crop.maxY))
        for handle in cropMode.handles {
            let p = viewPoint(handle.position(in: box))
            let square = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(square)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.stroke(square)
        }
        context.restoreGState()

        let action = cutsOut ? "cut out" : "crop"
        let label = NSAttributedString(string: "\(Int(crop.width)) × \(Int(crop.height))  ↩ \(action)  ⎋ cancel", attributes: [
            .font: NSFont.systemFont(ofSize: 11 / magnification, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ])
        label.draw(at: CGPoint(x: rect.minX, y: max(rect.minY - label.size().height - 2 * line, 0)))
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: tool == .select ? .arrow : .crosshair)
    }

    // MARK: Mouse

    /// The element of `kind` (text or speech bubble) at `point`, whose text a click with that tool edits.
    private func textAnnotation(at point: CGPoint, tolerance: CGFloat, kind: AnnotationKind) -> Annotation? {
        document.topmostAnnotation(at: point, tolerance: tolerance).flatMap { $0.kind == kind ? $0 : nil }
    }

    /// While a speech bubble is drawn its tail points next to where the drag began, away from the box, so it stays
    /// visible (upstream `SpeechbubbleContainer.HandleMouseMove`).
    private func drawnTail(origin: CGPoint, end: CGPoint) -> CGPoint {
        let offset = 20 * document.scale
        return CGPoint(x: origin.x + (end.x >= origin.x ? -offset : offset), y: origin.y + (end.y >= origin.y ? -offset : offset))
    }

    private func handle(at point: CGPoint, of a: Annotation) -> Handle? {
        let reach = 6 * pixelsPerScreenPoint
        return Handle.handles(for: a).first { Geometry.distance($0.position(in: a), point) <= reach }
    }

    override func mouseDown(with event: NSEvent) {
        let p = imagePoint(event)
        let tolerance = 5 * pixelsPerScreenPoint
        if isEditingText {
            commitEditing()
            if let kind = tool.kind, kind.hasEditableText {
                // With the text or speech bubble tool a click on another of its elements edits that one; anywhere else
                // it only finishes the text.
                if let hit = textAnnotation(at: p, tolerance: tolerance, kind: kind) { beginEditing(hit, isNew: false) }
                return
            }
        }
        window?.makeFirstResponder(self)

        // The handles of the selected element work with every tool.
        if selectedIDs.count == 1, let a = selectedAnnotation, tool != .crop, let handle = handle(at: p, of: a) {
            document.beginChange()
            drag = .resize(original: a, handle: handle)
            return
        }

        switch tool {
        case .select:
            let extend = !event.modifierFlags.intersection([.shift, .command]).isEmpty
            guard let a = document.topmostAnnotation(at: p, tolerance: tolerance) else {
                // On empty canvas a drag draws a rubber band that selects the elements inside it; with Shift or
                // Command they are added to the selection.
                if !extend { selectedIDs = [] }
                drag = .rubberBand(origin: p, kept: extend ? selectedIDs : [])
                return
            }
            if extend {
                // Shift- or Command-click adds an element to the selection or takes it out.
                if selectedIDs.contains(a.id) {
                    selectedIDs.removeAll { $0 == a.id }
                    return
                }
                selectedIDs.append(a.id)
            } else if !selectedIDs.contains(a.id) {
                selectedIDs = [a.id]
            } else {
                // A click on one of several selected elements keeps them selected (to move them together) and makes
                // it the primary one.
                selectedIDs.removeAll { $0 == a.id }
                selectedIDs.append(a.id)
            }
            if event.clickCount == 2 && a.kind.hasEditableText {
                beginEditing(a, isNew: false)
                return
            }
            if event.clickCount == 2 && a.kind == .emoji {
                // Upstream opens its emoji picker on a double click; here it is the system's Character Viewer.
                showEmojiPalette()
                return
            }
            if event.clickCount == 2 && a.kind == .barcode {
                // Upstream BarcodeContainer.OnDoubleClick opens the QR / barcode dialog again.
                editBarcode(a)
                return
            }
            document.beginChange()
            drag = .move(originals: selectedAnnotations, origin: p)

        case .crop:
            // A handle of the drawn area adjusts it (upstream `CropContainer`'s grippers); anywhere else starts anew.
            if let crop = cropRect, let handle = cropMode.handle(at: p, of: crop, reach: 6 * pixelsPerScreenPoint) {
                drag = .cropResize(original: crop, handle: handle)
                return
            }
            drag = .crop(origin: p)
            cropRect = nil

        case .counter, .emoji:
            // Placed with a click, centered on the mouse; dragging moves it.
            guard let kind = tool.kind else { return }
            let style = styleProvider(kind)
            // A counter is as big as its font, an emoji 64 × 64 (upstream `EmojiContainer.DefaultSize`).
            let radius = (kind == .counter ? CGFloat(style.fontSize) : 32) * document.scale
            let a = Annotation(kind: kind, start: CGPoint(x: p.x - radius, y: p.y - radius),
                               end: CGPoint(x: p.x + radius, y: p.y + radius), text: kind == .emoji ? emojiProvider() : "",
                               style: style)
            document.beginChange()
            document.add(a)
            select(a.id)
            drag = .move(originals: [a], origin: p)
            documentChanged()

        default:
            guard let kind = tool.kind else { return }
            if kind.hasEditableText, let hit = textAnnotation(at: p, tolerance: tolerance, kind: kind) {
                beginEditing(hit, isNew: false)
                return
            }
            var a = Annotation(kind: kind, start: p, end: p, style: styleProvider(kind))
            if kind == .freehand {
                a.points = [p]
                freehandSpacing = Geometry.freehandSpacing(sensitivity: appSettings.freehandSensitivity, scale: document.scale)
            }
            if kind == .speechBubble { a.tail = drawnTail(origin: p, end: p) }
            document.beginChange()
            document.add(a)
            select(a.id)
            drag = .create(id: a.id, origin: p)
            documentChanged()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        // Upstream Ctrl (`ScaleOptions.Centered`); Option is the Mac's "from the centre" key.
        let centered = event.modifierFlags.contains(.option)
        switch drag {
        case .create(let id, let origin):
            guard var a = document.annotation(id) else { return }
            if a.kind == .freehand {
                // Upstream `FreehandSensitivity`: a point only when it is far enough from the last one.
                if let last = a.points.last, Geometry.distance(last, p) < freehandSpacing { return }
                a.points.append(p)
            } else {
                var end = p
                if shift {
                    // Lines snap to 15 degrees (upstream `LineAngleRoundBehavior`), boxes become squares.
                    end = (a.kind == .line || a.kind == .arrow) ? Geometry.snapAngle(from: origin, to: p, degrees: 15)
                        : Geometry.squareEnd(from: origin, to: p)
                }
                a.start = centered ? Geometry.mirrored(end, around: origin) : origin
                a.end = end
                if a.kind == .speechBubble { a.tail = drawnTail(origin: a.start, end: end) }
            }
            document.update(a)
        case .move(let originals, let origin):
            var delta = CGVector(dx: p.x - origin.x, dy: p.y - origin.y)
            if shift {
                if abs(delta.dx) > abs(delta.dy) { delta.dy = 0 } else { delta.dx = 0 }
            }
            for original in originals {
                var moved = original
                moved.move(by: delta)
                document.update(moved)
            }
        case .resize(let original, let handle):
            var target = p
            if shift && (original.kind == .line || original.kind == .arrow) {
                target = Geometry.snapAngle(from: handle == .start ? original.end : original.start, to: p, degrees: 15)
            }
            // Shift keeps the aspect ratio of a box (upstream `ScaleOptions.Rational`), Option resizes around the centre.
            document.update(handle.drag(original, to: target, keepAspect: shift && original.kind.isBoxShaped, centered: centered))
        case .crop(let origin):
            guard tool == .crop else { return }
            cropRect = Geometry.cropSelection(cropMode, from: origin, to: p, imageSize: document.imageSize)
            autoscroll(with: event)
            return
        case .cropResize(let original, let handle):
            guard tool == .crop else { return }
            let resized = handle.drag(original, to: p).intersection(CGRect(origin: .zero, size: document.imageSize))
            cropRect = resized.isNull ? nil : resized
            autoscroll(with: event)
            return
        case .rubberBand(let origin, let kept):
            let band = Geometry.rect(from: origin, to: p)
            rubberBand = band
            // The selection follows the band while it is drawn (upstream selects on mouse up; this shows what a
            // release would select). Nothing in the document changes.
            let inside = document.annotations(within: band).map(\.id).filter { !kept.contains($0) }
            selectedIDs = kept + inside
            autoscroll(with: event)
            return
        }
        documentChanged()
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else { return }
        drag = nil
        switch current {
        case .create(let id, _):
            guard var a = document.annotation(id) else {
                document.endChange()
                return
            }
            if a.kind == .freehand, let last = a.points.last {
                // Upstream `FreehandContainer.HandleMouseUp` keeps the end point unless it is very close.
                let end = imagePoint(event)
                if Geometry.distance(last, end) >= freehandSpacing / 2 {
                    a.points.append(end)
                    document.update(a)
                }
            }
            let minimum = 3 * pixelsPerScreenPoint
            if a.kind == .cutMark {
                // A click makes a band with a small gap around the click (upstream `GetBandSize`); a drag at least
                // two teeth high.
                let teeth = CGFloat(a.style.toothHeight) * document.scale
                var band = a
                if a.bounds.height < minimum {
                    let height = CutMark.bandSize(toothHeight: teeth, gap: 10 * document.scale)
                    band.start = CGPoint(x: 0, y: a.start.y - height / 2)
                    band.end = CGPoint(x: 0, y: a.start.y + height / 2)
                } else if a.bounds.height < 2 * teeth {
                    band.end = CGPoint(x: 0, y: a.bounds.minY + 2 * teeth)
                }
                document.update(band)
                document.endChange()
                documentChanged()
                return
            }
            let tiny = a.kind == .freehand ? a.points.count < 2 : (a.bounds.width < minimum && a.bounds.height < minimum)
            if a.kind.hasEditableText {
                var box = a
                if tiny {
                    // A click makes a box of a default size. The tail of a speech bubble then points down left, where
                    // upstream puts the tail of a bubble that was not drawn.
                    box.end = CGPoint(x: a.start.x + 220 * document.scale,
                                      y: a.start.y + CGFloat(a.style.fontSize) * 2.4 * document.scale)
                    if box.kind == .speechBubble {
                        box.tail = CGPoint(x: box.bounds.minX - 20 * document.scale, y: box.bounds.maxY + 25 * document.scale)
                    }
                    document.update(box)
                }
                documentChanged()
                // The change stays open until the text is finished: creating and typing are one undo step.
                beginEditing(box, isNew: true)
                return
            }
            if tiny {
                document.remove(id)
                select(nil)
            }
            document.endChange()
        case .move, .resize:
            document.endChange()
        case .crop, .cropResize:
            if let crop = cropRect, crop.width < 2 || crop.height < 2 { cropRect = nil }
            return
        case .rubberBand:
            rubberBand = nil
            return
        }
        documentChanged()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = imagePoint(event)
        guard let a = document.topmostAnnotation(at: p, tolerance: 5 * pixelsPerScreenPoint) else { return nil }
        // The items without a target (Cut, Copy, Arrange) go through the responder chain from the canvas.
        commitEditing()
        window?.makeFirstResponder(self)
        if !selectedIDs.contains(a.id) { select(a.id) }
        let menu = NSMenu()
        if a.kind.hasEditableText && selectedIDs.count == 1 {
            menu.addItem(ClosureMenuItem(title: "Edit Text") { [weak self] in self?.beginEditing(a, isNew: false) })
        }
        if AnnotationKind.cutEdgeKinds.contains(a.kind) {
            // Upstream `CutMarkContainer` / `TornEdgeContainer.AddContextMenuItems`: new random edges, the settings, and
            // Apply to the image (of every selected cut mark and torn edges, like the property bar's button).
            if selectedIDs.count == 1 {
                menu.addItem(ClosureMenuItem(title: "New Random Edges") { [weak self] in
                    self?.editorWindowController?.newRandomEdges(a.id)
                })
                let settingsTitle = a.kind == .tornEdge ? "Torn Edge Settings…" : "Cut Edge Settings…"
                menu.addItem(ClosureMenuItem(title: settingsTitle) { [weak self] in
                    self?.editorWindowController?.showCutEdgeSettings(for: a.id)
                })
            }
            menu.addItem(ClosureMenuItem(title: "Apply to the Image") { [weak self] in
                guard let controller = self?.editorWindowController else { return }
                controller.applyToImage(controller.selectedCutEdgeIDs)
            })
        }
        if a.kind == .emoji && selectedIDs.count == 1 {
            let item = NSMenuItem(title: "Emoji", action: nil, keyEquivalent: "")
            item.submenu = emojiMenu()
            menu.addItem(item)
        }
        if a.kind == .barcode && selectedIDs.count == 1 {
            menu.addItem(ClosureMenuItem(title: "Edit QR / Barcode…") { [weak self] in self?.editBarcode(a) })
        }
        menu.addItem(withTitle: "Bring to Front", action: #selector(bringToFront(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Bring Forward", action: #selector(bringForward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Send Backward", action: #selector(sendBackward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Send to Back", action: #selector(sendToBack(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Duplicate", action: #selector(duplicate(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        // Upstream's Push out, Fit and Snap submenus (`DrawableContainerList.GetPushOutSubMenu` and the others).
        menu.addItem(submenu("Expand Capture and Move Outside", items: ElementEdge.allCases.map { edge in
            ClosureMenuItem(title: edge.title) { [weak self] in self?.pushOutSelection(to: edge) }
        }))
        menu.addItem(submenu("Stretch", items: [
            ClosureMenuItem(title: "Width") { [weak self] in self?.layoutSelection { self?.document.stretch($0, width: true) } },
            ClosureMenuItem(title: "Height") { [weak self] in self?.layoutSelection { self?.document.stretch($0, width: false) } },
        ]))
        menu.addItem(submenu("Dock to Edge", items: ElementEdge.allCases.map { edge in
            ClosureMenuItem(title: edge.title) { [weak self] in self?.layoutSelection { self?.document.dock($0, to: edge) } }
        }))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Delete") { [weak self] in self?.deleteSelection() })
        if document.canResetSize(selectedSet) {
            menu.addItem(ClosureMenuItem(title: "Reset Size") { [weak self] in self?.resetSelectionSize() })
        }
        return menu
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    /// Docks or stretches the selected elements as one undo step; upstream deselects them afterwards.
    private func layoutSelection(_ body: (Set<UUID>) -> Void) {
        commitEditing()
        let ids = selectedSet
        guard !ids.isEmpty else { return }
        document.change { body(ids) }
        documentChanged()
        selectedIDs = []
    }

    /// Upstream "Expand capture and move outside" of the (primary) selected element, one undo step.
    private func pushOutSelection(to edge: ElementEdge) {
        commitEditing()
        guard let id = selectedID else { return }
        var done = false
        document.change { done = document.pushOut(id, to: edge) }
        documentChanged()
        if done {
            selectedIDs = []
        } else {
            NSSound.beep()
        }
    }

    /// Upstream "Reset size": image elements go back to the size of their picture, one undo step.
    private func resetSelectionSize() {
        commitEditing()
        let ids = selectedSet
        document.change { document.resetSize(ids) }
        documentChanged()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control), flags.isDisjoint(with: [.command, .option]),
           styleShortcut(keyCode: Int(event.keyCode), shift: flags.contains(.shift)) {
            return
        }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelection()
            return
        case kVK_Escape:
            if cropRect != nil {
                cropRect = nil
            } else if !selectedIDs.isEmpty {
                selectedIDs = []
            } else {
                tool = .select
            }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if tool == .crop {
                applyCrop()
            } else if let a = selectedAnnotation, a.kind.hasEditableText {
                beginEditing(a, isNew: false)
            }
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            nudge(keyCode: Int(event.keyCode), far: flags.contains(.shift))
            return
        // Upstream's arrange keys: Home and End to the top and bottom, Page Up and Down one level.
        case kVK_Home where !selectedIDs.isEmpty:
            bringToFront(nil)
            return
        case kVK_End where !selectedIDs.isEmpty:
            sendToBack(nil)
            return
        case kVK_PageUp where !selectedIDs.isEmpty:
            bringForward(nil)
            return
        case kVK_PageDown where !selectedIDs.isEmpty:
            sendBackward(nil)
            return
        default:
            break
        }
        if flags.isDisjoint(with: [.command, .control, .option]), let char = event.charactersIgnoringModifiers?.lowercased().first {
            if char == "z" {
                // Upstream's Z: the resize dialog (Image › Resize…).
                NSApp.sendAction(#selector(EditorWindowController.resizeImage(_:)), to: nil, from: self)
                return
            }
            if let match = EditorTool.allCases.first(where: { $0.shortcut == char }) {
                choose(match)
                return
            }
        }
        super.keyDown(with: event)
    }

    /// Chooses a tool; C again while cropping goes to the next crop mode (upstream `ImageEditorFormKeyDown`).
    private func choose(_ chosen: EditorTool) {
        if chosen == .crop && tool == .crop {
            cycleCropMode()
        } else {
            tool = chosen
        }
    }

    /// The digit keys of the main row and the keypad.
    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_0: 0, kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4,
        kVK_ANSI_5: 5, kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad0: 0, kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4,
        kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

    /// Upstream `Surface.ProcessCmdKey` with Ctrl: 0–9 the fill colour (with Shift the line colour), plus and minus
    /// the line width (with Shift by 5), slash the shadow, of the selected elements. Keys, not characters, so Shift
    /// and the keyboard layout don't change them; the main row's = and - stand in for a missing keypad.
    private func styleShortcut(keyCode: Int, shift: Bool) -> Bool {
        guard !selectedIDs.isEmpty else { return false }
        if let digit = Self.digitKeys[keyCode], let color = ElementShortcuts.color(digit: digit, line: shift) {
            if shift {
                changeSelectionStyle(.lineColor) { $0.lineColor = color }
            } else {
                changeSelectionStyle(.fillColor) { $0.fillColor = color }
            }
            return true
        }
        let step: Double = shift ? 5 : 1
        switch keyCode {
        case kVK_ANSI_KeypadPlus, kVK_ANSI_Equal:
            changeSelectionStyle(.lineWidth) { $0.lineWidth = ElementShortcuts.lineWidth($0.lineWidth, changedBy: step) }
        case kVK_ANSI_KeypadMinus, kVK_ANSI_Minus:
            changeSelectionStyle(.lineWidth) { $0.lineWidth = ElementShortcuts.lineWidth($0.lineWidth, changedBy: -step) }
        case kVK_ANSI_KeypadDivide where !shift, kVK_ANSI_Slash where !shift:
            changeSelectionStyle(.shadow) { $0.shadow.toggle() }
        default:
            return false
        }
        return true
    }

    /// Changes `property` of the selected elements that have it (upstream `DrawableContainerList.SetForegroundColor`,
    /// `SetBackgroundColor`, `IncreaseLineThickness`, `FlipShadow`) as one undo step. The new value is remembered for
    /// new elements of those kinds, like upstream's field aggregator does, and the property bar shows it.
    private func changeSelectionStyle(_ property: AnnotationStyleProperty, _ change: (inout AnnotationStyle) -> Void) {
        let targets = selectedAnnotations.filter { $0.kind.has(property) }
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }
        var changed: [UUID: AnnotationStyle] = [:]
        document.change {
            for var element in targets {
                change(&element.style)
                document.update(element)
                changed[element.id] = element.style
            }
        }
        let shown = selectedID.flatMap { changed[$0] } ?? targets.last.flatMap { changed[$0.id] }
        if let shown, let store = editorWindowController?.settings {
            for kind in Set(targets.map(\.kind)) {
                var remembered = store.value.style(for: kind)
                remembered.copy(property, from: shown)
                store.update { $0.editorStyles[kind.rawValue] = remembered }
            }
        }
        documentChanged()
        onSelectionChange?()
    }

    /// Moves the selected elements one point (Shift: ten).
    private func nudge(keyCode: Int, far: Bool) {
        guard !selectedIDs.isEmpty else { return }
        let step = (far ? 10 : 1) * document.scale
        var delta = CGVector.zero
        switch keyCode {
        case kVK_LeftArrow: delta.dx = -step
        case kVK_RightArrow: delta.dx = step
        case kVK_UpArrow: delta.dy = -step
        default: delta.dy = step
        }
        // Pressing the arrow keys again moves the same elements in the same undo step (upstream
        // `MakeBoundsChangeUndoable(true)`).
        let key = "nudge " + selectedIDs.map(\.uuidString).sorted().joined(separator: " ")
        document.change(merging: key) { document.move(selectedSet, by: delta) }
        documentChanged()
    }

    func deleteSelection() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedSet
        document.change { document.remove(ids) }
        selectedIDs = []
        documentChanged()
    }

    /// Confirms the crop area (Return, the crop bar's Crop button): crops to it, or in the cut-out modes cuts its
    /// columns or rows out with the editor window's operations (upstream `Surface.ConfirmCrop`).
    func applyCrop() {
        guard let crop = cropRect else { return }
        switch cropMode {
        case .vertical:
            editorWindowController?.cutOutSelectedColumns(nil)
        case .horizontal:
            editorWindowController?.cutOutSelectedRows(nil)
        case .crop, .auto:
            document.change { document.cropKeepingEdges(to: crop) }
            cropRect = nil
            tool = .select
            documentChanged()
        }
    }

    func cancelCrop() {
        cropRect = nil
    }

    /// Applies an effect to the whole image as one undo step.
    func apply(_ effect: ImageEffect) {
        commitEditing()
        cropRect = nil
        document.change { document.apply(effect) }
        documentChanged()
    }

    // MARK: Emoji

    /// The emoji to pick from; picking one changes the selected emoji element.
    private func emojiMenu() -> NSMenu {
        let menu = NSMenu()
        for emoji in EmojiChoices.all {
            menu.addItem(ClosureMenuItem(title: emoji) { [weak self] in self?.onPickEmoji?(emoji) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "More Emoji…") { [weak self] in self?.showEmojiPalette() })
        return menu
    }

    /// The full emoji picker (upstream `Greenshot.Editor/Controls/Emoji`): the system's Character Viewer, which types
    /// the chosen emoji into the canvas (`insertText(_:replacementRange:)`).
    func showEmojiPalette() {
        commitEditing()
        window?.makeFirstResponder(self)
        NSApp.orderFrontCharacterPalette(nil)
    }

    // MARK: NSTextInputClient (only for the Character Viewer; keys are handled in keyDown)

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        guard let emoji = text.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) else { return }
        // For the selected emoji elements, or the next ones while the emoji tool is chosen.
        guard selectedAnnotations.contains(where: { $0.kind == .emoji }) || tool == .emoji else {
            NSSound.beep()
            return
        }
        onPickEmoji?(emoji)
    }

    override func doCommand(by selector: Selector) {}
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    /// Where the Character Viewer appears: next to the selected element.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rect = selectedAnnotation.map { viewRect($0.bounds) } ?? visibleRect
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    // MARK: Edit menu

    @objc func undo(_ sender: Any?) {
        if let textView {
            textView.undoManager?.undo()
            return
        }
        document.undo()
        documentChanged()
    }

    @objc func redo(_ sender: Any?) {
        if let textView {
            textView.undoManager?.redo()
            return
        }
        document.redo()
        documentChanged()
    }

    @objc func delete(_ sender: Any?) {
        deleteSelection()
    }

    /// Copies the selected elements (upstream `Surface.CutSelectedElements` / `CopySelectedElements`); with nothing
    /// selected Copy copies the image, like before.
    @objc func copy(_ sender: Any?) {
        commitEditing()
        guard !selectedIDs.isEmpty else {
            onCopy?()
            return
        }
        writeSelectionToPasteboard()
    }

    @objc func cut(_ sender: Any?) {
        commitEditing()
        guard !selectedIDs.isEmpty else { return }
        writeSelectionToPasteboard()
        deleteSelection()
    }

    /// Upstream `Surface.PasteElementFromClipboard`: copied elements, else image files, else a picture, else the
    /// pictures of pasted HTML (downloaded), else text as a text element.
    @objc func paste(_ sender: Any?) {
        commitEditing()
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: Self.elementsType), let transfer = ElementTransfer.decode(data) {
            let pasted = transfer.placed(in: document.imageSize, scale: document.scale, documentID: document.id,
                                         at: mouseImagePoint())
            insert(pasted)
            return
        }
        // Image files copied in the Finder (upstream reads the file list). Before the picture: the Finder puts the
        // file's icon on the clipboard too.
        let files = imageFileURLs(on: pasteboard)
        if !files.isEmpty {
            let elements = pictureElements(files.compactMap(ElementPictures.load), at: mouseImagePoint())
            if elements.isEmpty { NSSound.beep() } else { insert(elements) }
            return
        }
        // An image on the clipboard becomes an image element (upstream pastes it as an `ImageContainer`).
        if let pasted = Clipboard.image(), let a = pictureElement(pasted.image, scale: pasted.scale, at: mouseImagePoint()) {
            insert([a])
            return
        }
        let text = pasteboard.string(forType: .string).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if let html = pasteboard.string(forType: .html) {
            let urls = ElementClipboard.htmlImageURLs(in: html)
            if !urls.isEmpty {
                // Upstream adds nothing when no picture downloads; the text is more useful than nothing.
                addDownloadedPicture(from: urls, at: mouseImagePoint()) { [weak self] in
                    if let text { self?.insertPastedText(text) } else { NSSound.beep() }
                }
                return
            }
        }
        if let text {
            insertPastedText(text)
            return
        }
        NSSound.beep()
    }

    /// Pasted text as a text element at the mouse, else 40 % into the visible part of the image (upstream
    /// `GetPasteLocation(0.4f, 0.4f)`), selected.
    private func insertPastedText(_ text: String) {
        let visible = visibleRect.intersection(bounds)
        let origin = mouseImagePoint() ?? CGPoint(x: (visible.minX + visible.width * 0.4) * document.scale,
                                                  y: (visible.minY + visible.height * 0.4) * document.scale)
        insert([ElementClipboard.textElement(text, at: origin, base: styleProvider(.text), scale: document.scale,
                                             maxWidth: document.imageSize.width)])
    }

    /// Image elements for `pictures`, the first with its top left at `point`, each next one 10 points further.
    private func pictureElements(_ pictures: [(image: CGImage, scale: CGFloat)], at point: CGPoint?) -> [Annotation] {
        var origin = point
        var elements: [Annotation] = []
        for picture in pictures {
            guard let a = pictureElement(picture.image, scale: picture.scale, at: origin) else { continue }
            elements.append(a)
            origin = CGPoint(x: a.bounds.minX + 10 * document.scale, y: a.bounds.minY + 10 * document.scale)
        }
        return elements
    }

    /// Downloads the first of `urls` that is a picture and adds it at `point` (upstream `AddDownloadedOrFallbackAsync`);
    /// `fallback` runs when none is. Nothing happens when the window was closed meanwhile.
    private func addDownloadedPicture(from urls: [URL], at point: CGPoint?, fallback: @escaping () -> Void) {
        Task { [weak self] in
            let picture = await CanvasDownload.firstPicture(from: urls)
            guard let self, self.window != nil else { return }
            if let picture, let a = self.pictureElement(picture.image, scale: picture.scale, at: point) {
                self.commitEditing()
                self.insert([a])
            } else {
                fallback()
            }
        }
    }

    /// An image element for `picture`, its top left at `point`, else 10 points into the visible part of the image.
    private func pictureElement(_ picture: CGImage, scale: CGFloat, at point: CGPoint?) -> Annotation? {
        let visible = visibleRect.intersection(bounds)
        let origin = point ?? CGPoint(x: (visible.minX + 10) * document.scale, y: (visible.minY + 10) * document.scale)
        let room = CGSize(width: max(document.imageSize.width - origin.x, 1), height: max(document.imageSize.height - origin.y, 1))
        return Annotation.picture(picture, pictureScale: scale, at: origin, documentScale: document.scale, fitting: room)
    }

    // MARK: Drop

    private static let imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    private func imageFileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: Self.imageFileOptions) as? [URL] ?? []
    }

    /// A web link on the pasteboard: a URL, or text starting with "http" (upstream `OnDragDrop`).
    private func webURL(on pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if let url = urls.first(where: { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) { return url }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().hasPrefix("http"), let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func dropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        let usable = !imageFileURLs(on: pasteboard).isEmpty || NSImage.canInit(with: pasteboard) || webURL(on: pasteboard) != nil
        return usable ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    /// Dropped image files and pictures become image elements where they were dropped, each a little below the one
    /// before. A dropped link is downloaded first, so the picture comes in its original form; the dropped files or
    /// picture are the fallback (upstream `OnDragDrop`).
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        commitEditing()
        let pasteboard = sender.draggingPasteboard
        let drop = convert(sender.draggingLocation, from: nil)
        let origin = CGPoint(x: drop.x * document.scale, y: drop.y * document.scale)
        // The pasteboard is only readable during the drop: read everything now.
        var pictures = imageFileURLs(on: pasteboard).compactMap(ElementPictures.load)
        if pictures.isEmpty, let image = NSImage(pasteboard: pasteboard), let bitmap = ImageLoader.bitmap(of: image) {
            pictures = [bitmap]
        }
        let elements = pictureElements(pictures, at: origin)
        if let link = webURL(on: pasteboard) {
            addDownloadedPicture(from: [link], at: origin) { [weak self] in
                if elements.isEmpty { NSSound.beep() } else { self?.insert(elements) }
            }
            return true
        }
        insert(elements)
        return !elements.isEmpty
    }

    /// Upstream `Surface.DuplicateSelectedElements`: copies moved by 10, 10, selected instead of the originals.
    @objc func duplicate(_ sender: Any?) {
        commitEditing()
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedSet
        var copies: [Annotation] = []
        document.change { copies = document.duplicate(ids, offset: CGVector(dx: 10 * document.scale, dy: 10 * document.scale)) }
        documentChanged()
        selectedIDs = copies.map(\.id)
    }

    @objc override func selectAll(_ sender: Any?) {
        commitEditing()
        selectedIDs = document.annotations.map(\.id)
    }

    // MARK: Arrange (upstream `Surface.PullElementsToTop` / `PullElementsUp` / `PushElementsDown` / `PushElementsToBottom`)

    private func arrange(_ body: (Set<UUID>) -> Void) {
        commitEditing()
        let ids = selectedSet
        guard !ids.isEmpty else { return }
        document.change { body(ids) }
        documentChanged()
    }

    @objc func bringToFront(_ sender: Any?) { arrange(document.bringToFront) }
    @objc func bringForward(_ sender: Any?) { arrange(document.bringForward) }
    @objc func sendBackward(_ sender: Any?) { arrange(document.sendBackward) }
    @objc func sendToBack(_ sender: Any?) { arrange(document.sendToBack) }

    /// An item of the Object menu choosing a tool; its tag is the tool's index.
    @objc func selectTool(_ sender: NSMenuItem) {
        guard EditorTool.allCases.indices.contains(sender.tag) else { return }
        choose(EditorTool.allCases[sender.tag])
    }

    /// Adds elements as one undo step and selects them.
    func insert(_ elements: [Annotation]) {
        guard !elements.isEmpty else { return }
        document.change { document.add(elements) }
        documentChanged()
        selectedIDs = elements.map(\.id)
    }

    static let elementsType = NSPasteboard.PasteboardType(ElementTransfer.pasteboardType)

    private func writeSelectionToPasteboard() {
        let transfer = ElementTransfer(elements: selectedAnnotations, scale: document.scale, sourceDocument: document.id)
        guard let data = try? transfer.encoded() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.elementsType)
    }

    /// The mouse in image pixels when it is over the visible part of the canvas.
    private func mouseImagePoint() -> CGPoint? {
        guard let window else { return nil }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(p), bounds.contains(p) else { return nil }
        return CGPoint(x: p.x * document.scale, y: p.y * document.scale)
    }

    private var pasteboardHasElements: Bool {
        NSPasteboard.general.availableType(from: [Self.elementsType]) != nil
    }

    private var canPaste: Bool {
        let pasteboard = NSPasteboard.general
        return pasteboardHasElements || NSImage.canInit(with: pasteboard) || pasteboard.availableType(from: [.string, .html]) != nil
            || !imageFileURLs(on: pasteboard).isEmpty
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // While a crop waits for Return or Esc only the tools stay (upstream disables the rest for a confirmable
        // element, `ToolStripItemEndisabler`).
        if tool == .crop, cropRect != nil, item.action != #selector(selectTool(_:)) { return false }
        switch item.action {
        case #selector(undo(_:)): return textView?.undoManager?.canUndo ?? document.canUndo
        case #selector(redo(_:)): return textView?.undoManager?.canRedo ?? document.canRedo
        case #selector(delete(_:)), #selector(cut(_:)), #selector(duplicate(_:)): return !selectedIDs.isEmpty
        case #selector(paste(_:)): return canPaste
        case #selector(selectAll(_:)): return !document.annotations.isEmpty
        case #selector(bringToFront(_:)), #selector(bringForward(_:)): return document.canBringForward(selectedSet)
        case #selector(sendToBack(_:)), #selector(sendBackward(_:)): return document.canSendBackward(selectedSet)
        case #selector(selectTool(_:)):
            // The tools have single-letter shortcuts: only while the canvas has the keyboard, so that typing into a
            // text element or a field of the property bar isn't taken by the menu.
            item.state = EditorTool.allCases.firstIndex(of: tool) == item.tag ? .on : .off
            return window?.firstResponder === self
        default: return true
        }
    }

    // MARK: Text

    func beginEditing(_ a: Annotation, isNew: Bool) {
        commitEditing()
        if !isNew { document.beginChange() }
        editingID = a.id
        select(a.id)
        textUndoManager = UndoManager()
        let style = a.style
        // The element stays drawn without its text (frame, fill, a bubble's shape) around the text field; a box too
        // small for its frame gets the field over all of it.
        let inside = AnnotationRenderer.textRect(for: a, scale: document.scale)
        let frame = inside.isNull || inside.width < document.scale || inside.height < document.scale ? a.bounds : inside
        let textView = AlignedTextView(frame: viewRect(frame))
        textView.string = a.text
        // The same font and alignment as the renderer, so the text doesn't jump when editing ends.
        textView.font = AnnotationRenderer.font(for: style, size: CGFloat(style.fontSize))
        textView.textColor = NSColor(cgColor: style.lineColor.cgColor)
        textView.insertionPointColor = NSColor(cgColor: style.lineColor.cgColor) ?? .textColor
        textView.alignment = AnnotationRenderer.alignment(of: style)
        textView.verticalAlignment = style.verticalAlignment
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.delegate = self
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1 / magnification
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        addSubview(textView)
        self.textView = textView
        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
        textView.alignVertically()
        rendered = nil
        needsDisplay = true
    }

    /// Finishes the text being edited. Empty text removes the element.
    func commitEditing() {
        guard let textView, let id = editingID else { return }
        self.textView = nil
        editingID = nil
        textUndoManager?.removeAllActions()
        textUndoManager = nil
        let text = textView.string
        textView.removeFromSuperview()
        if var a = document.annotation(id) {
            // An empty text shows nothing; an empty speech bubble still shows its shape, so it stays.
            if a.kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.remove(id)
                selectedIDs.removeAll { $0 == id }
            } else {
                a.text = text
                document.update(a)
            }
        }
        document.endChange()
        window?.makeFirstResponder(self)
        documentChanged()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndoManager
    }

    /// Esc, and Return without a modifier, finish the text; Shift-, Option- or Control-Return start a new line
    /// (upstream `TextContainer.textBox_KeyDown`).
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitEditing()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.shift, .option, .control, .command]) ?? []
            if modifiers.isEmpty {
                commitEditing()
            } else {
                textView.insertNewlineIgnoringFieldEditor(nil)
            }
            return true
        }
        if selector == #selector(NSResponder.insertLineBreak(_:)) || selector == #selector(NSResponder.insertParagraphSeparator(_:)) {
            // Control-Return and friends: a plain new line, not a Unicode line or paragraph separator in the text.
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        return false
    }

    /// Lets the box grow downwards while typing.
    func textDidChange(_ notification: Notification) {
        guard let textView, let id = editingID, var a = document.annotation(id),
              let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let needed = layout.usedRect(for: container).height + textView.textContainerInset.height * 2 + 4
        let growth = needed - textView.frame.height
        textView.alignVertically()
        guard growth > 0 else { return }
        textView.setFrameSize(NSSize(width: textView.frame.width, height: needed))
        textView.alignVertically()
        let box = a.bounds
        a.start = box.origin
        a.end = CGPoint(x: box.maxX, y: box.maxY + growth * document.scale)
        document.update(a)
        // A speech bubble is drawn below the text field and grows with it.
        rendered = nil
        needsDisplay = true
    }
}

/// The in-place text editor: places its text at the top, middle or bottom of the box like the renderer does
/// (NSTextView itself always starts at the top).
final class AlignedTextView: NSTextView {
    var verticalAlignment: VerticalTextAlignment = .center
    private var topOffset: CGFloat = 0

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y + topOffset)
    }

    /// Call after the text or the frame changed.
    func alignVertically() {
        guard let container = textContainer, let layout = layoutManager else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let room = max(0, bounds.height - used - textContainerInset.height * 2)
        let offset: CGFloat
        switch verticalAlignment {
        case .top: offset = 0
        case .center: offset = (room / 2).rounded(.down)
        case .bottom: offset = room
        }
        guard offset != topOffset else { return }
        topOffset = offset
        invalidateTextContainerOrigin()
        needsDisplay = true
    }
}

/// Keeps a smaller image in the middle of the scroll view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let size = documentView.frame.size
        if rect.width > size.width { rect.origin.x = (size.width - rect.width) / 2 }
        if rect.height > size.height { rect.origin.y = (size.height - rect.height) / 2 }
        return rect
    }
}

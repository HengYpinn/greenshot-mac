// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

/// The drawing surface of the editor (upstream `Surface`). The view is sized in points; the document works in
/// image pixels, so a Retina capture shows at its real size.
@MainActor
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    let document: EditorDocument
    /// The style new elements of a kind get (the last used one).
    var styleProvider: (AnnotationKind) -> AnnotationStyle = { .defaults(for: $0) }
    var onDocumentChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onToolChange: (() -> Void)?
    var onCopy: (() -> Void)?

    var tool: EditorTool = .select {
        didSet {
            guard oldValue != tool else { return }
            commitEditing()
            if case .crop = drag { drag = nil }
            if oldValue == .crop || tool == .crop { cropRect = nil }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            onToolChange?()
        }
    }

    private(set) var selectedID: UUID? {
        didSet {
            guard oldValue != selectedID else { return }
            needsDisplay = true
            onSelectionChange?()
        }
    }

    /// The crop rectangle being drawn, image pixels.
    private(set) var cropRect: CGRect? {
        didSet {
            needsDisplay = true
            onToolChange?()
        }
    }

    private enum Drag {
        case create(id: UUID, origin: CGPoint)
        case move(original: Annotation, origin: CGPoint)
        case resize(original: Annotation, handle: Handle)
        case crop(origin: CGPoint)
    }

    private var drag: Drag?
    private var rendered: CGImage?
    private var textView: NSTextView?
    private var editingID: UUID?
    /// The typing undo of one text editing session, thrown away when it ends (not left on the window's manager).
    private var textUndoManager: UndoManager?

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        setFrameSize(pointSize)
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
        if let id = selectedID, document.annotation(id) == nil { selectedID = nil }
        needsDisplay = true
        onDocumentChange?()
    }

    func select(_ id: UUID?) {
        selectedID = id
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if rendered == nil {
            rendered = AnnotationRenderer.flatten(base: document.baseImage, annotations: document.annotations,
                                                  scale: document.scale, hiding: editingID)
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
    }

    private func drawSelection(in context: CGContext) {
        guard let a = selectedAnnotation, a.id != editingID else { return }
        let line = 1 / magnification
        let accent = NSColor.controlAccentColor.cgColor
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

    private func drawCrop(in context: CGContext) {
        guard tool == .crop, let crop = cropRect else { return }
        let rect = viewRect(crop)
        let line = 1 / magnification
        context.saveGState()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(rect)
        context.addPath(path)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillPath(using: .evenOdd)
        context.setLineWidth(line)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineDash(phase: 0, lengths: [5 * line, 4 * line])
        context.stroke(rect)
        context.restoreGState()

        let label = NSAttributedString(string: "\(Int(crop.width)) × \(Int(crop.height))  ↩ crop  ⎋ cancel", attributes: [
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

    private func textAnnotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        document.topmostAnnotation(at: point, tolerance: tolerance).flatMap { $0.kind == .text ? $0 : nil }
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
            if tool == .text {
                // With the text tool a click on another text edits it; anywhere else it only finishes the text.
                if let hit = textAnnotation(at: p, tolerance: tolerance) { beginEditing(hit, isNew: false) }
                return
            }
        }
        window?.makeFirstResponder(self)

        // The handles of the selected element work with every tool.
        if let a = selectedAnnotation, tool != .crop, let handle = handle(at: p, of: a) {
            document.beginChange()
            drag = .resize(original: a, handle: handle)
            return
        }

        switch tool {
        case .select:
            guard let a = document.topmostAnnotation(at: p, tolerance: tolerance) else {
                selectedID = nil
                return
            }
            selectedID = a.id
            if event.clickCount == 2 && a.kind == .text {
                beginEditing(a, isNew: false)
                return
            }
            document.beginChange()
            drag = .move(original: a, origin: p)

        case .crop:
            drag = .crop(origin: p)
            cropRect = nil

        case .counter:
            let style = styleProvider(.counter)
            let radius = CGFloat(style.fontSize) * document.scale
            let a = Annotation(kind: .counter, start: CGPoint(x: p.x - radius, y: p.y - radius),
                               end: CGPoint(x: p.x + radius, y: p.y + radius), style: style)
            document.beginChange()
            document.add(a)
            selectedID = a.id
            drag = .move(original: a, origin: p)
            documentChanged()

        default:
            guard let kind = tool.kind else { return }
            if kind == .text, let hit = textAnnotation(at: p, tolerance: tolerance) {
                beginEditing(hit, isNew: false)
                return
            }
            var a = Annotation(kind: kind, start: p, end: p, style: styleProvider(kind))
            if kind == .freehand { a.points = [p] }
            document.beginChange()
            document.add(a)
            selectedID = a.id
            drag = .create(id: a.id, origin: p)
            documentChanged()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .create(let id, let origin):
            guard var a = document.annotation(id) else { return }
            if a.kind == .freehand {
                // Upstream FreehandSensitivity: skip points closer than a few pixels.
                if let last = a.points.last, Geometry.distance(last, p) < 3 * pixelsPerScreenPoint / 2 { return }
                a.points.append(p)
            } else {
                var end = p
                if shift {
                    end = (a.kind == .line || a.kind == .arrow) ? Geometry.snap45(from: origin, to: p) : Geometry.squareEnd(from: origin, to: p)
                }
                a.start = origin
                a.end = end
            }
            document.update(a)
        case .move(let original, let origin):
            var delta = CGVector(dx: p.x - origin.x, dy: p.y - origin.y)
            if shift {
                if abs(delta.dx) > abs(delta.dy) { delta.dy = 0 } else { delta.dx = 0 }
            }
            var moved = original
            moved.move(by: delta)
            document.update(moved)
        case .resize(let original, let handle):
            var target = p
            if shift && (original.kind == .line || original.kind == .arrow) {
                target = Geometry.snap45(from: handle == .start ? original.end : original.start, to: p)
            }
            document.update(handle.drag(original, to: target))
        case .crop(let origin):
            guard tool == .crop else { return }
            cropRect = Geometry.rect(from: origin, to: p).intersection(CGRect(origin: .zero, size: document.imageSize))
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
            guard let a = document.annotation(id) else {
                document.endChange()
                return
            }
            let minimum = 3 * pixelsPerScreenPoint
            let tiny = a.kind == .freehand ? a.points.count < 2 : (a.bounds.width < minimum && a.bounds.height < minimum)
            if a.kind == .text {
                var box = a
                if tiny {
                    // A click makes a text box of a default size.
                    box.end = CGPoint(x: a.start.x + 220 * document.scale,
                                      y: a.start.y + CGFloat(a.style.fontSize) * 2.4 * document.scale)
                    document.update(box)
                }
                documentChanged()
                // The change stays open until the text is finished: creating and typing are one undo step.
                beginEditing(box, isNew: true)
                return
            }
            if tiny {
                document.remove(id)
                selectedID = nil
            }
            document.endChange()
        case .move, .resize:
            document.endChange()
        case .crop:
            if let crop = cropRect, crop.width < 2 || crop.height < 2 { cropRect = nil }
            return
        }
        documentChanged()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = imagePoint(event)
        guard let a = document.topmostAnnotation(at: p, tolerance: 5 * pixelsPerScreenPoint) else { return nil }
        selectedID = a.id
        let menu = NSMenu()
        if a.kind == .text {
            menu.addItem(ClosureMenuItem(title: "Edit Text") { [weak self] in self?.beginEditing(a, isNew: false) })
        }
        menu.addItem(ClosureMenuItem(title: "Bring to Front") { [weak self] in
            self?.document.change { self?.document.bringToFront(a.id) }
            self?.documentChanged()
        })
        menu.addItem(ClosureMenuItem(title: "Send to Back") { [weak self] in
            self?.document.change { self?.document.sendToBack(a.id) }
            self?.documentChanged()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Delete") { [weak self] in self?.deleteSelection() })
        return menu
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelection()
            return
        case kVK_Escape:
            if cropRect != nil {
                cropRect = nil
            } else if selectedID != nil {
                selectedID = nil
            } else {
                tool = .select
            }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if tool == .crop {
                applyCrop()
            } else if let a = selectedAnnotation, a.kind == .text {
                beginEditing(a, isNew: false)
            }
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            nudge(keyCode: Int(event.keyCode), far: flags.contains(.shift))
            return
        default:
            break
        }
        if flags.isDisjoint(with: [.command, .control, .option]),
           let char = event.charactersIgnoringModifiers?.lowercased().first,
           let match = EditorTool.allCases.first(where: { $0.shortcut == char }) {
            tool = match
            return
        }
        super.keyDown(with: event)
    }

    /// Moves the selected element one point (Shift: ten).
    private func nudge(keyCode: Int, far: Bool) {
        guard let a = selectedAnnotation else { return }
        let step = (far ? 10 : 1) * document.scale
        var delta = CGVector.zero
        switch keyCode {
        case kVK_LeftArrow: delta.dx = -step
        case kVK_RightArrow: delta.dx = step
        case kVK_UpArrow: delta.dy = -step
        default: delta.dy = step
        }
        var moved = a
        moved.move(by: delta)
        document.change { document.update(moved) }
        documentChanged()
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        document.change { document.remove(id) }
        selectedID = nil
        documentChanged()
    }

    func applyCrop() {
        guard let crop = cropRect else { return }
        document.change { document.crop(to: crop) }
        cropRect = nil
        tool = .select
        documentChanged()
    }

    func cancelCrop() {
        cropRect = nil
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

    @objc func copy(_ sender: Any?) {
        onCopy?()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return textView?.undoManager?.canUndo ?? document.canUndo
        case #selector(redo(_:)): return textView?.undoManager?.canRedo ?? document.canRedo
        case #selector(delete(_:)): return selectedID != nil
        default: return true
        }
    }

    // MARK: Text

    func beginEditing(_ a: Annotation, isNew: Bool) {
        commitEditing()
        if !isNew { document.beginChange() }
        editingID = a.id
        selectedID = a.id
        textUndoManager = UndoManager()
        let style = a.style
        let textView = NSTextView(frame: viewRect(a.bounds))
        textView.string = a.text
        textView.font = AnnotationRenderer.font(for: style, size: CGFloat(style.fontSize))
        textView.textColor = NSColor(cgColor: style.lineColor.cgColor)
        textView.insertionPointColor = NSColor(cgColor: style.lineColor.cgColor) ?? .textColor
        textView.alignment = .center
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = style.fillColor.isVisible
        textView.backgroundColor = NSColor(cgColor: style.fillColor.cgColor) ?? .clear
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.delegate = self
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1 / magnification
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        addSubview(textView)
        self.textView = textView
        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
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
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.remove(id)
                selectedID = nil
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

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitEditing()
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
        guard needed > textView.frame.height else { return }
        textView.setFrameSize(NSSize(width: textView.frame.width, height: needed))
        let box = a.bounds
        a.start = box.origin
        a.end = CGPoint(x: box.maxX, y: box.minY + needed * document.scale)
        document.update(a)
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

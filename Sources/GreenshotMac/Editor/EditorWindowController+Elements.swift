// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Editor")

extension Capture {
    /// The picture the editor opens: without the mouse pointer when the pointer comes as its own element.
    var editorImage: CGImage { pointer == nil ? image : (imageWithoutPointer ?? image) }
}

extension Notification.Name {
    /// The selection of a canvas changed; the object is the canvas.
    static let canvasSelectionDidChange = Notification.Name("GreenshotCanvasSelectionDidChange")
}

/// The elements with their own commands: torn edges and cut marks (upstream `TornEdgeContainer`, `CutMarkContainer`:
/// new random edges, their settings, Apply to the image) and the captured mouse pointer (upstream `CursorContainer`).
extension EditorWindowController {
    /// The property bar's buttons for cut marks and torn edges: Apply to the Image (upstream `btnApplyToImage`).
    func cutEdgeActionViews() -> [NSView] {
        [CutEdgeApplyButton(canvas: canvas, target: self, action: #selector(applySelectionToImage(_:)))]
    }

    /// Adds the captured mouse pointer as an element, part of the opened capture (no undo step), and selects it like
    /// upstream `Surface(ICapture)` does.
    func addCapturedPointer(of capture: Capture) {
        guard let id = editorDocument.addPointer(capture.pointer) else { return }
        canvas.documentChanged()
        canvas.select(id)
    }

    /// The selected cut marks and torn edges.
    var selectedCutEdgeIDs: Set<UUID> {
        Set(canvas.selectedAnnotations.filter { AnnotationKind.cutEdgeKinds.contains($0.kind) }.map(\.id))
    }

    /// Upstream `BtnApplyToImageClick`: draws the selected cut marks and torn edges into the image, one undo step.
    @objc func applySelectionToImage(_ sender: Any?) {
        applyToImage(selectedCutEdgeIDs)
    }

    /// Draws the cut marks and torn edges among `ids` into the image (upstream `Surface.ApplyElementToImage`), which
    /// deselects everything.
    func applyToImage(_ ids: Set<UUID>) {
        guard !ids.isEmpty, performImageOperation({ $0.applyToImage(ids) }) else {
            NSSound.beep()
            return
        }
        canvas.select(nil)
    }

    /// Effects › Torn Edges (upstream `TornEdgesToolStripMenuItemMouseUp` → `Surface.AddTornEdges`): torn edges as an
    /// element with the torn edge settings, selected; when there are torn edges already, those are selected.
    func addTornEdges() {
        let torn = settings.value.tornEdgeSettings
        let style = settings.value.style(for: .tornEdge)
        var added: UUID?
        performImageOperation { document in
            added = document.addTornEdges(torn, style: style)
            return added != nil
        }
        if let added {
            canvas.select(added)
        } else {
            log.info("Torn edges could not be added: the canvas could not grow by the room for the shadow")
            NSSound.beep()
        }
    }

    /// Upstream "New random edge" (`CutMarkContainer` / `TornEdgeContainer` `NewSeed`), one undo step.
    func newRandomEdges(_ id: UUID) {
        guard var element = editorDocument.annotation(id) else { return }
        element.seed = .random(in: .min ... .max)
        editorDocument.change { editorDocument.update(element) }
        canvas.documentChanged()
    }

    /// Upstream "Torn edge settings" / "Cut edge settings…" of an element: the torn edge dialog with the element's
    /// settings (without the sides for a cut mark); OK changes only this element, one undo step.
    func showCutEdgeSettings(for id: UUID) {
        guard let element = editorDocument.annotation(id) else { return }
        let torn = element.kind == .tornEdge
        let form = TornEdgeSettingsForm(element.cutEdgeSettings, showEdges: torn)
        let message = torn ? String(localized: "The torn edges of this image.") : String(localized: "The edges and the shadow of this cut mark.")
        let title = torn ? String(localized: "Torn Edge Settings") : String(localized: "Cut Edge Settings")
        EffectSettingsDialog.run(title: title, message: message,
                                 content: form.view, owner: form, for: window) { [weak self] in
            guard let self, let current = self.editorDocument.annotation(id) else { return }
            let changed = current.applyingCutEdgeSettings(form.settings, scale: self.editorDocument.scale)
            self.editorDocument.change { self.editorDocument.update(changed) }
            self.canvas.documentChanged()
            self.refreshProperties()
        }
    }
}

/// The property bar's Apply to the Image button (upstream `btnApplyToImage`): the group shows for the cut mark kinds,
/// also while the Cut Mark tool is chosen with nothing selected, so the button is only enabled while a cut mark or torn
/// edges are selected.
final class CutEdgeApplyButton: NSButton {
    private weak var canvas: CanvasView?

    init(canvas: CanvasView, target: AnyObject, action: Selector) {
        self.canvas = canvas
        super.init(frame: .zero)
        title = String(localized: "Apply to the Image")
        image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        imagePosition = .imageLeading
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        toolTip = String(localized: "Draw the selected cut edges or torn edges into the image; they can't be changed afterwards")
        self.target = target
        self.action = action
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged(_:)), name: .canvasSelectionDidChange,
                                               object: canvas)
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectionChanged(_ notification: Notification) {
        refresh()
    }

    private func refresh() {
        isEnabled = canvas?.selectedAnnotations.contains { AnnotationKind.cutEdgeKinds.contains($0.kind) } == true
    }
}

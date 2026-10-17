// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Barcode")

extension CanvasView {
    /// A double click on a barcode element opens the QR / barcode dialog for it (upstream
    /// `BarcodeContainer.OnDoubleClick` → `ZxingModel.OnDoubleClick`); Apply changes the element as one undo step.
    func editBarcode(_ a: Annotation) {
        guard let window else { return }
        commitEditing()
        let sheet = BarcodeSheet(spec: a.barcode ?? BarcodeSpec(), editing: true)
        sheet.onApply = { [weak self] spec in
            guard let self, let element = self.document.annotation(a.id) else { return }
            let edited = element.withEditedBarcode(spec, scale: self.document.scale)
            self.document.change { self.document.update(edited) }
            self.documentChanged()
            log.info("Changed a barcode element to \(spec.symbology.rawValue)")
        }
        sheet.begin(for: window)
    }
}

extension EditorWindowController {
    /// Edit › Insert QR / Barcode… (upstream `ZxingEditorPlugin`): the dialog, then the code as an element near the top
    /// left of the image, selected, as one undo step.
    @objc func insertBarcode(_ sender: Any?) {
        guard let window else { return }
        canvas.commitEditing()
        let sheet = BarcodeSheet()
        sheet.onApply = { [weak self] spec in
            guard let self else { return }
            let document = self.editorDocument
            var element = Annotation.insertedBarcode(spec, imageSize: document.imageSize, scale: document.scale)
            element.style = self.canvas.styleProvider(.barcode)
            self.canvas.insert([element])
            log.info("Inserted a \(spec.symbology.rawValue) element")
        }
        sheet.begin(for: window)
    }
}

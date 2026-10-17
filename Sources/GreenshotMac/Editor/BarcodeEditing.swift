// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension CanvasView {
    /// A double click on a barcode element opens the QR / barcode dialog for it (upstream
    /// `BarcodeContainer.OnDoubleClick`). Package E2 fills it in.
    func editBarcode(_ a: Annotation) {}
}

extension EditorWindowController {
    /// Edit › Insert QR / Barcode… (upstream `ZxingEditorPlugin`). Package E2 fills it in.
    @objc func insertBarcode(_ sender: Any?) {}
}

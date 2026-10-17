// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension Snapshots {
    /// Renders for the QR / barcode generator: its dialog and barcode elements.
    static func renderBarcodeExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let qr = BarcodeSheet()
        let wifi = BarcodeSheet()
        wifi.set {
            $0.qrType = .wifi
            $0.wifiSSID = "Greenshot"
            $0.wifiPassword = "correct horse"
            $0.roundedDots = true
            $0.foreground = RGBAColor(red: 0, green: 0.2, blue: 0.5)
        }
        let error = BarcodeSheet(spec: BarcodeSpec(), editing: true)
        error.set {
            $0.symbology = .ean13
            $0.text = "59012341234a"
        }
        let bars = BarcodeSheet()
        bars.set {
            $0.symbology = .code128
            $0.text = "Greenshot-128"
            $0.margin = 4
        }
        // The sheets own their controls; keep them alive until the renders are written.
        keepAlive += [qr, wifi, error, bars]
        try write(form(qr.contentView ?? NSView()), to: folder.appendingPathComponent("dialog-barcode-qr.png"))
        try write(form(wifi.contentView ?? NSView()), to: folder.appendingPathComponent("dialog-barcode-wifi.png"))
        try write(form(error.contentView ?? NSView()), to: folder.appendingPathComponent("dialog-barcode-error.png"))
        try write(form(bars.contentView ?? NSView()), to: folder.appendingPathComponent("dialog-barcode-code128.png"))
        try write(canvasBarcodes(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-barcodes.png"))
        try write(canvasBarcodeStyles(sample: sample, settings: settings),
                  to: folder.appendingPathComponent("canvas-barcode-styles.png"))
    }

    private static func barcode(_ symbology: BarcodeSymbology, _ text: String, at origin: CGPoint, size: CGSize? = nil,
                                _ change: (inout BarcodeSpec) -> Void = { _ in }) -> Annotation {
        var spec = BarcodeSpec()
        spec.symbology = symbology
        spec.text = text
        change(&spec)
        var element = Annotation.barcodeElement(spec, at: origin, scale: 2)
        if let size { element.end = CGPoint(x: origin.x + size.width, y: origin.y + size.height) }
        return element
    }

    /// All 15 formats as elements on a capture; the QR code is selected (corner handles: it keeps its aspect ratio).
    private static func canvasBarcodes(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        let matrices: [(BarcodeSymbology, String)] = [
            (.qrCode, "https://getgreenshot.org"), (.aztec, "Greenshot for Mac"), (.dataMatrix, "Greenshot"),
            (.pdf417, "Greenshot PDF-417"),
        ]
        var elements: [Annotation] = []
        for (index, (symbology, text)) in matrices.enumerated() {
            elements.append(barcode(symbology, text, at: CGPoint(x: 60 + index * 620, y: 60)))
        }
        let bars: [(BarcodeSymbology, String)] = [
            (.code128, "Greenshot-128"), (.code39, "GREENSHOT"), (.code93, "TEST93"), (.ean13, "590123412345"),
            (.ean8, "9638507"), (.upcA, "03600029145"), (.upcE, "0425261"), (.codabar, "12345"),
            (.itf, "12345678"), (.msi, "1234567"), (.plessey, "12345AB"),
        ]
        for (index, (symbology, text)) in bars.enumerated() {
            let origin = CGPoint(x: 60 + (index % 4) * 620, y: 560 + (index / 4) * 300)
            elements.append(barcode(symbology, text, at: origin, size: CGSize(width: 560, height: 180)))
        }
        doc.add(elements)
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.canvas.select(elements[0].id)
        }
    }

    /// Round dots (QR, Aztec, Data Matrix), colours, a transparent background with a shadow, and margins 0, 4 and 10.
    private static func canvasBarcodeStyles(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        let url = "https://getgreenshot.org"
        var shadowed = barcode(.qrCode, url, at: CGPoint(x: 1960, y: 60)) {
            $0.background = .clear
            $0.foreground = RGBAColor(red: 0.6, green: 0, blue: 0)
        }
        shadowed.style.shadow = true
        doc.add([
            barcode(.qrCode, url, at: CGPoint(x: 60, y: 60)) { $0.roundedDots = true },
            barcode(.aztec, "Greenshot for Mac", at: CGPoint(x: 680, y: 60)) { $0.roundedDots = true },
            barcode(.qrCode, url, at: CGPoint(x: 1300, y: 60)) {
                $0.foreground = RGBAColor(red: 0, green: 0, blue: 0.5)
                $0.background = .yellow
                $0.margin = 4
            },
            shadowed,
            barcode(.dataMatrix, "Greenshot", at: CGPoint(x: 60, y: 700)) { $0.roundedDots = true },
            barcode(.ean13, "590123412345", at: CGPoint(x: 680, y: 700), size: CGSize(width: 560, height: 200)) { $0.margin = 0 },
            barcode(.ean13, "590123412345", at: CGPoint(x: 1300, y: 700), size: CGSize(width: 560, height: 200)) { $0.margin = 4 },
            barcode(.ean13, "590123412345", at: CGPoint(x: 1920, y: 700), size: CGSize(width: 560, height: 200)) { $0.margin = 10 },
        ])
        return editorWindow(doc, settings: settings) { $0.canvas.tool = .select }
    }
}

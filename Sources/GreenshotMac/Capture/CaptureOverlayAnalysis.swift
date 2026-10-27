// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The menu of a clicked QR code on the capture screen (upstream's Zxing hotspot menu: copy the content, open a URL).
/// Drawn by the capture screen itself: a real `NSMenu` would open below the overlay's screen saver level.
struct BarcodeMenu {
    struct Item {
        var title: String
        var action: BarcodeAction
        /// Quartz global points.
        var frame: CGRect
    }

    static let font = NSFont.menuFont(ofSize: 13)
    static let itemHeight: CGFloat = 24

    var barcode: DetectedBarcode
    var items: [Item]
    var hovered: Int?
    /// Quartz global points.
    var frame: CGRect

    /// The menu with its top left corner at `point`, kept inside `display`.
    init(barcode: DetectedBarcode, at point: CGPoint, display: CGRect) {
        self.barcode = barcode
        var entries: [(String, BarcodeAction)] = [(String(localized: "Copy “\(Self.shortened(barcode.payload))”", comment: "Menu item for a QR code: copies its text"), .copy(barcode.payload))]
        if let url = barcode.url { entries.append((String(localized: "Open \(Self.shortened(url.absoluteString))", comment: "Menu item for a QR code: opens its link"), .open(url))) }
        let width = entries.map { NSAttributedString(string: $0.0, attributes: [.font: Self.font]).size().width }.max() ?? 0
        var frame = CGRect(x: point.x + 2, y: point.y + 2, width: max(width + 28, 160),
                           height: CGFloat(entries.count) * Self.itemHeight + 8)
        frame.origin.x = max(display.minX + 4, min(frame.minX, display.maxX - frame.width - 4))
        frame.origin.y = max(display.minY + 4, min(frame.minY, display.maxY - frame.height - 4))
        self.frame = frame
        items = entries.enumerated().map { index, entry in
            Item(title: entry.0, action: entry.1,
                 frame: CGRect(x: frame.minX + 4, y: frame.minY + 4 + CGFloat(index) * Self.itemHeight,
                               width: frame.width - 8, height: Self.itemHeight))
        }
    }

    mutating func hover(at point: CGPoint) {
        hovered = items.firstIndex { $0.frame.contains(point) }
    }

    /// The first line, at most 40 characters.
    static func shortened(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }
}

/// The background work of the capture screen: text recognition for the text mode (upstream
/// `Greenshot/Capturing/Tools/TextCaptureTool.cs`) and QR codes (upstream
/// `Greenshot.Plugin.Zxing/Processing/ZxingCaptureProcessor.cs`). Both run once per capture, off the main thread, with
/// the async Vision calls (the sync ones would block a thread of the cooperative pool).
extension CaptureOverlayController {
    /// Recognises the text of every display, once per capture; the lines show up when it is done.
    func startTextRecognition() {
        guard textLines == nil, !recognizingText else { return }
        recognizingText = true
        let jobs = plainScreens.map { (image: $0.image, scale: $0.scale, origin: $0.frame.origin) }
        let language = ocrLanguage
        Task { [weak self] in
            let lines = await Task.detached(priority: .userInitiated) {
                var lines: [RecognizedLine] = []
                for job in jobs {
                    guard let found = try? await TextRecognizer.recognizeLines(in: job.image, language: language) else { continue }
                    lines += TextCaptureSelection.global(found, scale: job.scale, origin: job.origin)
                }
                return lines
            }.value
            self?.useTextLines(lines)
        }
    }

    /// The recognised lines (global points); also for the snapshots, which have no time to wait.
    func useTextLines(_ lines: [RecognizedLine]) {
        guard !finished else { return }
        textLines = lines
        recognizingText = false
        mouseMoved(to: cursor)
    }

    /// Looks for QR codes on every display, once per capture.
    func startBarcodeDetection() {
        let jobs = plainScreens.map { (image: $0.image, scale: $0.scale, origin: $0.frame.origin) }
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                var found: [DetectedBarcode] = []
                for job in jobs {
                    guard let codes = try? await BarcodeDetector.detect(in: job.image) else { continue }
                    for code in codes {
                        var global = code
                        global.bounds = Geometry.globalRect(fromPixels: code.bounds, scale: job.scale, origin: job.origin)
                            .insetBy(dx: -4, dy: -4)
                        found.append(global)
                    }
                }
                return found
            }.value
            self?.useBarcodes(found)
        }
    }

    /// The QR codes found (global points); also for the snapshots.
    func useBarcodes(_ found: [DetectedBarcode]) {
        guard !finished else { return }
        barcodes = found
        mouseMoved(to: cursor)
    }

    func openBarcodeMenu(for barcode: DetectedBarcode, at point: CGPoint) {
        let display = screen(at: point)?.frame ?? desktopBounds
        barcodeMenu = BarcodeMenu(barcode: barcode, at: point, display: display)
        barcodeMenu?.hover(at: point)
        redraw()
    }

    /// A click while the QR code menu is open: an item ends the capture, anywhere else closes the menu.
    func pickBarcodeMenuItem(at point: CGPoint) {
        guard let menu = barcodeMenu else { return }
        if let item = menu.items.first(where: { $0.frame.contains(point) }) {
            finish(OverlaySelection(rect: menu.barcode.bounds, window: nil, barcodeAction: item.action))
        } else {
            barcodeMenu = nil
            mouseMoved(to: point)
        }
    }

    /// Mouse up in the text mode: a click captures the line under the mouse (unless `copiesLine` is false: then it
    /// selects nothing), a drag the words it touched.
    func finishText(clickedAt point: CGPoint, copiesLine: Bool) {
        guard let start = anchor else { return }
        if let rect = selection, rect.width >= 3 || rect.height >= 3 {
            finishText(in: rect)
        } else if copiesLine, let line = TextCaptureSelection.line(at: start, in: textLines ?? []) {
            finish(OverlaySelection(rect: line.bounds, window: nil, text: line.text, mode: .text))
        } else {
            cancelSelection()
        }
    }

    /// Captures the words in `rect`; nothing happens when it has none.
    func finishText(in rect: CGRect) {
        let lines = textLines ?? []
        let words = TextCaptureSelection.selectedWords(in: rect, lines: lines).flatMap { $0 }
        guard !words.isEmpty else {
            NSSound.beep()
            cancelSelection()
            return
        }
        let bounds = words.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        finish(OverlaySelection(rect: bounds, window: nil, text: TextCaptureSelection.text(in: rect, lines: lines), mode: .text))
    }
}

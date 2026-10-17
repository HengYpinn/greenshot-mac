// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// "QR code actions": copy or open what the QR codes in the screenshot say. Port of upstream
/// `Greenshot.Plugin.Zxing/Destinations/ZxingQrDestination.cs`, with the Vision framework instead of ZXing.
@MainActor
enum QRCodeDestination {
    /// Looks for codes off the main thread and calls back on it.
    static func detect(in image: CGImage, completion: @escaping ([DetectedBarcode]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let codes = (try? BarcodeDetector.detect(in: image)) ?? []
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(codes) }
            }
        }
    }

    /// "Copy: …" for every code, and "Open: …" for those that are links.
    static func items(for codes: [DetectedBarcode], saver: ImageSaver) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for code in codes {
            let payload = code.payload
            items.append(ClosureMenuItem(title: "Copy: \(shortened(payload))") {
                Clipboard.copy(text: payload)
                saver.notify("Copied the QR code's text", detail: shortened(payload))
            })
            if let url = code.url {
                items.append(ClosureMenuItem(title: "Open: \(shortened(url.absoluteString))") { NSWorkspace.shared.open(url) })
            }
        }
        return items
    }

    /// The picker's submenu: filled once the codes are found (an open menu updates). Without codes `noCodes` runs
    /// (the picker then removes its entry, like upstream offers QR code actions only when codes were found).
    static func pickerSubmenu(for capture: Capture, saver: ImageSaver, noCodes: @escaping () -> Void = {}) -> NSMenu {
        let menu = NSMenu(title: "QR Code")
        menu.autoenablesItems = false
        let searching = NSMenuItem(title: "Looking for QR codes…", action: nil, keyEquivalent: "")
        searching.isEnabled = false
        menu.addItem(searching)
        detect(in: capture.image) { [weak menu] codes in
            guard let menu else { return }
            menu.removeAllItems()
            let found = items(for: codes, saver: saver)
            if found.isEmpty {
                let none = NSMenuItem(title: "No QR code found", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
                noCodes()
            }
            found.forEach(menu.addItem)
        }
        return menu
    }

    /// The destination: a menu at the mouse with the actions, or a message without codes (upstream counts both as
    /// done).
    static func show(_ capture: Capture, saver: ImageSaver, popUp: @escaping (NSMenu) -> Void,
                     completion: @escaping ExportCompletion = { _ in }) {
        detect(in: capture.image) { codes in
            guard !codes.isEmpty else {
                saver.notify("No QR code found", detail: "Nothing in the screenshot could be read as a QR code.", kind: .warning)
                completion(.succeeded(clearsModified: false))
                return
            }
            let menu = NSMenu(title: "QR Code")
            menu.autoenablesItems = false
            items(for: codes, saver: saver).forEach(menu.addItem)
            popUp(menu)
            completion(.succeeded(clearsModified: false))
        }
    }

    private static func shortened(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }
}

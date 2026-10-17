// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// "Save as PDF": port of upstream `Greenshot.Plugin.Pdf/Destinations/PdfDestination.cs`. As an automatic
/// destination it writes into the output folder like "Save directly"; from the picker or the File menu it asks.
@MainActor
enum PdfDestination {
    /// The Save As dialog starts where the image Save As does (the pattern's sub folder, the last folder, the output
    /// folder).
    @discardableResult
    static func save(_ capture: Capture, settings: SettingsStore, saver: ImageSaver, ask: Bool) -> ExportResult {
        var url: URL
        if ask {
            let panel = NSSavePanel()
            panel.title = String(localized: "Save Screenshot as PDF")
            panel.allowedContentTypes = [.pdf]
            guard let chosen = saver.runSavePanel(panel, title: capture.title, date: capture.date, fileExtension: "pdf") else {
                return .declined
            }
            url = chosen
        } else {
            url = saver.defaultURL(title: capture.title, date: capture.date, fileExtension: "pdf")
            if !settings.value.allowOverwrite { url = DestinationSupport.uniqueURL(for: url) }
        }
        do {
            try PdfLayout.write(capture.image, scale: capture.scale, settings: settings.value.pdf, title: capture.title, to: url)
        } catch {
            ErrorPresenter.show(error, title: String(localized: "The PDF could not be saved"))
            return .failed(error.localizedDescription)
        }
        // Upstream's PDF destination doesn't copy the path.
        saver.notifySaved(url, copyPath: false)
        return .succeeded(fileURL: url)
    }
}

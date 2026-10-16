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
    @discardableResult
    static func save(_ capture: Capture, settings: SettingsStore, saver: ImageSaver, ask: Bool) -> URL? {
        var url = saver.defaultURL(title: capture.title, date: capture.date, fileExtension: "pdf")
        if ask {
            let panel = NSSavePanel()
            panel.title = "Save Screenshot as PDF"
            panel.canCreateDirectories = true
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.allowedContentTypes = [.pdf]
            NSApp.activate()
            guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
            url = chosen
        } else if !settings.value.allowOverwrite {
            url = DestinationSupport.uniqueURL(for: url)
        }
        do {
            try PdfLayout.write(capture.image, scale: capture.scale, settings: settings.value.pdf, title: capture.title, to: url)
        } catch {
            ErrorPresenter.show(error, title: "The PDF could not be saved")
            return nil
        }
        saver.notifySaved(url)
        return url
    }
}

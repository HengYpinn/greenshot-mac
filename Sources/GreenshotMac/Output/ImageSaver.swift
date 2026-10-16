// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// Writes images to files, with the output folder and filename pattern of the settings.
@MainActor
final class ImageSaver {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// The file "Save directly" writes to: the output folder plus the filled filename pattern.
    func defaultURL(title: String, date: Date, format: ImageFormat? = nil) -> URL {
        let s = settings.value
        let name = FilenamePattern.fileName(s.filenamePattern, context: settings.patternContext(title: title, date: date))
        let ext = (format ?? s.outputFormat).fileExtension
        let base = name.hasPrefix("/") ? URL(fileURLWithPath: name) : s.outputFolderURL.appendingPathComponent(name)
        return base.appendingPathExtension(ext)
    }

    /// Upstream's "Save directly": no dialog. Returns the file, or nil after showing the error.
    @discardableResult
    func saveDirectly(_ image: CGImage, title: String, date: Date) -> URL? {
        let url = defaultURL(title: title, date: date)
        guard write(image, to: url) else { return nil }
        let s = settings.value
        if s.copyPathToClipboard && !s.destinations.contains(.clipboard) {
            Clipboard.copy(text: url.path)
        }
        notifySaved(url)
        return url
    }

    /// Asks for a file name and format. Returns the file, or nil when cancelled or failed.
    @discardableResult
    func saveAs(_ image: CGImage, title: String, date: Date, suggestedURL: URL? = nil) -> URL? {
        let s = settings.value
        let writable = suggestedURL.flatMap { ImageFormat(fileExtension: $0.pathExtension) }
        let initialFormat = writable ?? s.outputFormat
        var suggested = suggestedURL ?? defaultURL(title: title, date: date, format: initialFormat)
        if writable == nil, suggestedURL != nil {
            // e.g. a HEIC file opened in the editor: offer the same name in a format this app writes.
            suggested = suggested.deletingPathExtension().appendingPathExtension(initialFormat.fileExtension)
        }
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.canCreateDirectories = true
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.allowedContentTypes = [initialFormat.utType]
        let accessory = FormatAccessory(panel: panel, format: initialFormat)
        panel.accessoryView = accessory.view
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let format = ImageFormat(fileExtension: url.pathExtension) ?? accessory.format
        guard write(image, to: url, format: format) else { return nil }
        notifySaved(url)
        return url
    }

    @discardableResult
    func write(_ image: CGImage, to url: URL, format: ImageFormat? = nil) -> Bool {
        let s = settings.value
        let format = format ?? ImageFormat(fileExtension: url.pathExtension) ?? s.outputFormat
        do {
            try ImageExporter.write(image, to: url, format: format, quality: s.jpegQuality)
            return true
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be saved")
            return false
        }
    }

    func notifySaved(_ url: URL) {
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        notify("Saved \(url.lastPathComponent)", detail: "\(folder) – click to show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func notify(_ message: String, detail: String? = nil, action: (() -> Void)? = nil) {
        guard settings.value.showNotifications else { return }
        Toast.show(message, detail: detail, action: action)
    }
}

/// The format popup under the save panel.
@MainActor
private final class FormatAccessory: NSObject {
    let view: NSView
    private(set) var format: ImageFormat
    private weak var panel: NSSavePanel?
    private let popup = NSPopUpButton()

    init(panel: NSSavePanel, format: ImageFormat) {
        self.panel = panel
        self.format = format
        let label = NSTextField(labelWithString: "Format:")
        let stack = NSStackView(views: [label, popup])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view = stack
        super.init()
        for candidate in ImageFormat.allCases {
            popup.addItem(withTitle: candidate.displayName)
            popup.lastItem?.representedObject = candidate.rawValue
        }
        popup.selectItem(at: ImageFormat.allCases.firstIndex(of: format) ?? 0)
        popup.target = self
        popup.action = #selector(changed)
        // The panel holds the accessory view, the view holds nothing: keep this object alive with it.
        objc_setAssociatedObject(view, "FormatAccessory", self, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc private func changed() {
        guard let raw = popup.selectedItem?.representedObject as? String, let selected = ImageFormat(rawValue: raw) else { return }
        format = selected
        panel?.allowedContentTypes = [selected.utType]
    }
}

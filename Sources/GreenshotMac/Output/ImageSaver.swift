// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

private let log = Log("Save")

/// Writes images to files, with the output folder and filename pattern of the settings: port of upstream
/// `Greenshot/Destinations/FileDestination.cs`, `FileWithDialogDestination.cs` and `SaveImageFileDialog.cs`.
@MainActor
final class ImageSaver {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// How a write ended.
    enum WriteOutcome {
        case written
        /// The quality dialog was cancelled.
        case cancelled
        case failed(Error)
    }

    /// The output folder with its pattern variables filled in (upstream `FillVariables(OutputFilePath)`).
    func outputFolderURL(title: String, date: Date) -> URL {
        DestinationSupport.outputFolder(settings.value.outputFolder,
                                        context: settings.patternContext(title: title, date: date, consumeNumber: false))
    }

    /// The file "Save directly" writes to: the output folder plus the filled filename pattern.
    func defaultURL(title: String, date: Date, format: ImageFormat? = nil) -> URL {
        defaultURL(title: title, date: date, fileExtension: (format ?? settings.value.outputFormat).fileExtension)
    }

    /// The same for any extension (e.g. "pdf").
    func defaultURL(title: String, date: Date, fileExtension: String) -> URL {
        let s = settings.value
        // The folder first: it only previews ${NUM}, the name counts it up.
        let folder = outputFolderURL(title: title, date: date)
        let name = FilenamePattern.fileName(s.filenamePattern, context: settings.patternContext(title: title, date: date))
        let base = name.hasPrefix("/") ? URL(fileURLWithPath: name) : folder.appendingPathComponent(name)
        return base.appendingPathExtension(fileExtension)
    }

    /// Upstream's "Save directly": no dialog. Returns the file, or nil after showing the error. Without "Allow
    /// overwrite" an existing file's name gets " (2)", " (3)", …. `editable` is what a `.greenshot` file keeps (an
    /// editor's document); without it such a file has `image` without elements.
    @discardableResult
    func saveDirectly(_ image: CGImage, scale: CGFloat, title: String, date: Date,
                      editable: GreenshotFile.Contents? = nil) -> URL? {
        exportDirectly(image, scale: scale, title: title, date: date, editable: editable).fileURL
    }

    /// "Save directly" as an export (upstream `FileDestination.ExportAsync`): a file that can't be written shows the
    /// problem and then the Save As dialog.
    func exportDirectly(_ image: CGImage, scale: CGFloat, title: String, date: Date,
                        editable: GreenshotFile.Contents? = nil) -> ExportResult {
        var url = defaultURL(title: title, date: date)
        if !settings.value.allowOverwrite { url = DestinationSupport.uniqueURL(for: url) }
        switch writeResult(image, scale: scale, to: url, title: title, date: date, editable: editable) {
        case .written:
            notifySaved(url)
            return .succeeded(fileURL: url)
        case .cancelled:
            return .declined
        case .failed(let error):
            // Upstream `error_save`: say so, then ask where to save instead (no write access, a bad name, a full disk).
            let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            ErrorPresenter.show(message: "The screenshot could not be saved, please choose another place",
                                detail: "\(url.lastPathComponent) could not be written to \(folder): \(error.localizedDescription)")
            return exportAs(image, scale: scale, title: title, date: date, fileName: url.lastPathComponent,
                            editable: editable)
        }
    }

    /// Asks for a file name and format. Returns the file, or nil when cancelled or failed.
    @discardableResult
    func saveAs(_ image: CGImage, scale: CGFloat, title: String, date: Date, suggestedURL: URL? = nil,
                editable: GreenshotFile.Contents? = nil) -> URL? {
        exportAs(image, scale: scale, title: title, date: date, suggestedURL: suggestedURL, editable: editable).fileURL
    }

    /// "Save as" as an export (upstream `FileWithDialogDestination`). `suggestedURL` is the editor's own file: the dialog
    /// starts there. `fileName` replaces the pattern's name. `editable` as for `saveDirectly`.
    func exportAs(_ image: CGImage, scale: CGFloat, title: String, date: Date, suggestedURL: URL? = nil,
                  fileName: String? = nil, editable: GreenshotFile.Contents? = nil) -> ExportResult {
        let s = settings.value
        let writable = suggestedURL.flatMap { ImageFormat(fileExtension: $0.pathExtension) }
        let initialFormat = writable ?? s.outputFormat
        var name = fileName
        if let suggestedURL, writable == nil {
            // e.g. a HEIC file opened in the editor: offer the same name in a format this app writes.
            name = suggestedURL.deletingPathExtension().appendingPathExtension(initialFormat.fileExtension).lastPathComponent
        }
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.allowedContentTypes = [initialFormat.utType]
        let accessory = FormatAccessory(panel: panel, format: initialFormat)
        panel.accessoryView = accessory.view
        guard var url = runSavePanel(panel, title: title, date: date, fileExtension: initialFormat.fileExtension,
                                     editorFile: suggestedURL, fileName: name) else { return .declined }
        // A name without an extension this app writes gets the one of the chosen format (upstream
        // `SaveImageFileDialog.FileNameWithExtension`) instead of a PNG called "shot.xyz".
        let format: ImageFormat
        if let typed = ImageFormat(fileExtension: url.pathExtension) {
            format = typed
        } else {
            format = accessory.format
            url = url.appendingPathExtension(format.fileExtension)
        }
        switch writeResult(image, scale: scale, to: url, format: format, title: title, date: date, editable: editable) {
        case .written:
            notifySaved(url)
            return .succeeded(fileURL: url)
        case .cancelled:
            return .declined
        case .failed(let error):
            // Upstream `error_nowriteaccess`.
            let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            ErrorPresenter.show(message: "The screenshot could not be saved to \(url.lastPathComponent)",
                                detail: "Check that you can write to \(folder).\n\n\(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Runs a save panel where upstream's `SaveImageFileDialog` starts: in the folder of the editor's own file, else in
    /// the sub folder the filename pattern makes (created for the dialog and removed again when nothing was saved in
    /// it), else in the folder of the last saved file, else in the output folder. The name is the pattern's.
    func runSavePanel(_ panel: NSSavePanel, title: String, date: Date, fileExtension: String, editorFile: URL? = nil,
                      fileName: String? = nil) -> URL? {
        panel.canCreateDirectories = true
        let output = outputFolderURL(title: title, date: date)
        let suggested = editorFile ?? defaultURL(title: title, date: date, fileExtension: fileExtension)
        var created: [URL] = []
        var patternFolder: URL?
        if editorFile == nil {
            let folder = suggested.deletingLastPathComponent()
            if folder.standardizedFileURL.path != output.standardizedFileURL.path {
                // NSSavePanel ignores a folder that isn't there, so it is made now (upstream `_eagerlyCreatedDirectory`).
                created = Self.createFolders(folder)
                if Self.isFolder(folder) { patternFolder = folder }
            }
        }
        panel.directoryURL = DestinationSupport.saveAsFolder(editorFile: editorFile, patternSubfolder: patternFolder,
                                                             lastSavedFile: settings.value.lastSavedFile, outputFolder: output,
                                                             folderExists: Self.isFolder)
        panel.nameFieldStringValue = fileName ?? suggested.lastPathComponent
        NSApp.activate()
        let response = panel.runModal()
        // Also after OK: the write makes the folder again when the file goes there.
        Self.removeUnused(created)
        return response == .OK ? panel.url : nil
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Creates `folder` and the missing folders above it; returns the ones it made, the deepest first.
    private static func createFolders(_ folder: URL) -> [URL] {
        var missing: [URL] = []
        var current = folder.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            missing.append(current)
            current = current.deletingLastPathComponent()
        }
        guard !missing.isEmpty, (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return []
        }
        return missing
    }

    /// Removes the folders made for the dialog that are still empty, the deepest first (upstream `CleanUp`).
    private static func removeUnused(_ folders: [URL]) {
        for folder in folders {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
                  DestinationSupport.isUnused(folderContents: contents) else { return }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// `scale` is the pixels per point, written as the file's resolution so it opens at its real size. Asks with the
    /// quality dialog first when "Show the quality dialog" is on (false when cancelled); shows the error when the
    /// file can't be written.
    @discardableResult
    func write(_ image: CGImage, scale: CGFloat, to url: URL, format: ImageFormat? = nil) -> Bool {
        switch writeResult(image, scale: scale, to: url, format: format) {
        case .written:
            return true
        case .cancelled:
            return false
        case .failed(let error):
            ErrorPresenter.show(error, title: "The screenshot could not be saved")
            return false
        }
    }

    /// `write` without the error dialog. A `.greenshot` file keeps `editable` (an editor's document), or else `image`
    /// without elements with `title` and `date`.
    func writeResult(_ image: CGImage, scale: CGFloat, to url: URL, format: ImageFormat? = nil, title: String = "",
                     date: Date? = nil, editable: GreenshotFile.Contents? = nil) -> WriteOutcome {
        let s = settings.value
        let format = format ?? ImageFormat(fileExtension: url.pathExtension) ?? s.outputFormat
        if format == .greenshot {
            // Upstream 5172972a: the greenshot format is written from the surface (its elements), not the rendered image.
            let contents = editable
                ?? GreenshotFile.Contents(image: image, scale: scale, title: title.isEmpty ? nil : title, captureDate: date)
            do {
                try contents.write(to: url)
                log.info("Saved a .greenshot file with \(contents.elements.count) elements")
                return .written
            } catch {
                log.error("Saving \(url.lastPathComponent) failed", error: error)
                return .failed(error)
            }
        }
        var options = ImageOutputOptions(settings: s, format: format, scale: scale)
        if s.promptJpegQuality, DestinationSupport.asksQuality(format) {
            // Upstream `QualityWindow` (FileDestination asks before every save when OutputFilePromptQuality is on).
            guard let choice = QualityForm.ask(format: format, settings: settings) else { return .cancelled }
            options.jpegQuality = choice.quality
            options.reduceColors = choice.reduceColors
        }
        do {
            try ImageExporter.write(image, to: url, options: options)
            return .written
        } catch {
            return .failed(error)
        }
    }

    /// Records the file for "Open Recent Capture", copies its path when "Copy the file path" is on (upstream
    /// `OutputFileCopyPathToClipboard`, after every save of an image; not when the Clipboard destination put the
    /// screenshot there) and says where it went.
    func notifySaved(_ url: URL, copyPath: Bool = true) {
        settings.update { $0.lastSavedFile = url.path }
        let s = settings.value
        if copyPath, s.copyPathToClipboard, !s.destinations.contains(.clipboard) {
            Clipboard.copy(text: url.path)
        }
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        notify("Saved \(url.lastPathComponent)", detail: "\(folder) – click to show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// A toast, filtered by Settings › Output › Messages. "Show a message after saving or copying" turns off the
    /// information ones only; warnings and errors follow the message level alone.
    func notify(_ message: String, detail: String? = nil, kind: MessageKind = .info, action: (() -> Void)? = nil) {
        let s = settings.value
        guard s.notificationLevel.shows(kind), kind != .info || s.showNotifications else { return }
        Toast.show(message, detail: detail, kind: kind, action: action)
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

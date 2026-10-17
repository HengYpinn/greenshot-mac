// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

extension GreenshotFile.Contents {
    /// Saving must not write over the file these contents came from: Greenshot for Windows wrote it (it would only show
    /// the image of the file this app writes), or some of its elements could not be read (they would be lost).
    public var savesToNewFile: Bool {
        if case .windows = origin { return true }
        return elementsFailed || !unreadable.isEmpty
    }

    /// What the editor says after opening the file: `openMessage`, and that Save asks for a new file when it does.
    public var openStatus: String? {
        guard let message = openMessage else { return nil }
        if case .windows = origin { return message }
        return savesToNewFile ? message + " Save asks for a new file, so this one keeps them." : message
    }
}

extension EditorDocument {
    /// The document of an opened `.greenshot` file (upstream `ImageIO.LoadGreenshotSurface`): its image and elements,
    /// unchanged, saved to `url` unless `savesToNewFile`.
    public convenience init(opening contents: GreenshotFile.Contents, from url: URL) {
        self.init(image: contents.image, scale: contents.scale, title: url.deletingPathExtension().lastPathComponent,
                  captureDate: contents.captureDate ?? Date(), fileURL: url, isModified: false)
        addOpened(contents.elements)
        counterStart = contents.counterStart
        savesToNewFile = contents.savesToNewFile
    }

    /// A kept editor opened again at the next start: still unsaved, saved to the file it showed (when that is still
    /// there, `fileExists`) and as careful with it as before.
    public convenience init(restoring contents: GreenshotFile.Contents, fileExists: (URL) -> Bool) {
        let original = contents.session?.originalFile.map { URL(fileURLWithPath: $0) }
        self.init(image: contents.image, scale: contents.scale, title: contents.title ?? "Screenshot",
                  captureDate: contents.captureDate ?? Date(), fileURL: original.flatMap { fileExists($0) ? $0 : nil })
        addOpened(contents.elements)
        counterStart = contents.counterStart
        savesToNewFile = contents.session?.savesToNewFile ?? false
    }
}

extension GreenshotFile {
    /// Writes the document as a `.greenshot` file to `url` (folders are made), which becomes its file.
    public static func write(_ document: EditorDocument, to url: URL) throws {
        let data = try Contents(of: document).encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        document.fileURL = url
        document.savesToNewFile = false
    }

    /// Save of a document whose file is a `.greenshot` file: written over it, unless it `savesToNewFile`; then nothing
    /// is written and the result is false (Save asks for a new file).
    public static func saveInPlace(_ document: EditorDocument) throws -> Bool {
        guard let url = document.fileURL, !document.savesToNewFile else { return false }
        try write(document, to: url)
        return true
    }
}

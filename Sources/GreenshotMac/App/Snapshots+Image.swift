// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension Snapshots {
    /// Renders for image operations, effect dialogs and output formats. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderImageExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let removeTransparency = RemoveTransparencyForm()
        keepAlive.append(removeTransparency)
        try write(form(removeTransparency.view), to: folder.appendingPathComponent("dialog-remove-transparency.png"))
        try renderObfuscationPreview(to: folder, sample: sample, settings: settings)
        try renderPixelation(to: folder, sample: sample)
        try renderRoundTrips(to: folder, sample: sample)
    }

    /// The sample written with the formats that have their own encoder, read back with ImageIO and saved as PNG to look
    /// at: `export-roundtrip-<format>.png`.
    private static func renderRoundTrips(to folder: URL, sample: CGImage) throws {
        for format in [ImageFormat.tga, .pbm, .ico, .webp] {
            let data = try ImageExporter.data(for: sample, options: ImageOutputOptions(format: format, scale: 2))
            guard let decoded = ImageFileLoader.load(data: data) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "\(format) did not read back"])
            }
            try ImageExporter.write(decoded.image, to: folder.appendingPathComponent("export-roundtrip-\(format.rawValue).png"),
                                    format: .png, scale: decoded.scale)
        }
    }

    /// The Obfuscate Text dialog after a search, and the editor with its preview elements. The sample's text lines
    /// are given as text recognition would find them (image pixels), so no Vision is needed.
    private static func renderObfuscationPreview(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let saved = settings.value.textObfuscation
        defer { settings.update { $0.textObfuscation = saved } }
        settings.update {
            $0.textObfuscation.searchPattern = #"\d"#
            $0.textObfuscation.useRegex = true
        }
        let texts = ["Revenue grew in every region this quarter.", "Contact: support@example.com  Order 4711-0815",
                     "Next review: Thursday at 10:00"]
        let lines = texts.enumerated().map { index, text -> RecognizedLine in
            let top = 820 + CGFloat(index) * 60
            var x: CGFloat = 200
            let words = text.split(separator: " ").map { word -> RecognizedWord in
                let w = RecognizedWord(text: String(word), bounds: CGRect(x: x, y: top, width: CGFloat(word.count) * 20, height: 48))
                x += CGFloat(word.count + 1) * 20
                return w
            }
            return RecognizedLine(text: text, bounds: CGRect(x: 200, y: top, width: CGFloat(text.count) * 20, height: 48), words: words)
        }
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        var sheet: TextObfuscationSheet?
        let editor = editorWindow(doc, settings: settings) { controller in
            let made = controller.textObfuscationSheet(lines: lines)
            made.searchNow()
            sheet = made
        }
        try write(editor, to: folder.appendingPathComponent("editor-obfuscate-preview.png"))
        if let sheet {
            keepAlive.append(sheet)
            try write(form(sheet.contentView ?? NSView()), to: folder.appendingPathComponent("dialog-obfuscate-text-matches.png"))
        }
    }

    /// A close look at the pixelate that can't be reversed: the sample's text lines under a pixelate element.
    private static func renderPixelation(to folder: URL, sample: CGImage) throws {
        var style = AnnotationStyle.defaults(for: .obfuscate)
        style.pixelSize = 6
        let element = Annotation(kind: .obfuscate, start: CGPoint(x: 180, y: 800), end: CGPoint(x: 1200, y: 990), style: style)
        guard let flat = AnnotationRenderer.flatten(base: sample, annotations: [element], scale: 2),
              let crop = flat.cropping(to: CGRect(x: 120, y: 740, width: 1200, height: 320)) else { return }
        try ImageExporter.write(crop, to: folder.appendingPathComponent("pixelate-sample.png"), format: .png, scale: 2)
    }
}

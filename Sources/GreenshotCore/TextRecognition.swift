// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Vision

/// A recognised word, in pixels of the image it was found in (origin top left, like the rest of the editor).
public struct RecognizedWord: Equatable, Sendable {
    public var text: String
    public var bounds: CGRect

    public init(text: String, bounds: CGRect) {
        self.text = text
        self.bounds = bounds
    }
}

/// A recognised line of text with its words (upstream `DetectedOcrLine`).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var bounds: CGRect
    public var words: [RecognizedWord]

    public init(text: String, bounds: CGRect, words: [RecognizedWord]) {
        self.text = text
        self.bounds = bounds
        self.words = words
    }
}

/// Text recognition with the Vision framework: the Mac's stand-in for upstream's Windows OCR
/// (`Greenshot/Destinations/Win10OcrDestination.cs`, `Greenshot/Capturing/Tools/TextCaptureTool.cs`).
public enum TextRecognizer {
    /// The lines of text in `image`, top to bottom. `language` is a BCP 47 code; empty picks automatically.
    ///
    /// Blocks the calling thread until Vision is done, and Vision waits for work on a thread of Swift's cooperative
    /// pool. Call it only on a GCD queue or a thread of your own, never in a task or an async function (with as many
    /// calls at once as the pool has threads, they wait for each other forever): there, `await` the async overload.
    public static func recognizeLines(in image: CGImage, language: String = "") throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !language.isEmpty { request.recognitionLanguages = [language] }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let observations = request.results ?? []
        var lines: [RecognizedLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let lineBounds = pixelRect(observation.boundingBox, width: width, height: height)
            var words: [RecognizedWord] = []
            for range in wordRanges(in: text) {
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                words.append(RecognizedWord(text: String(text[range]), bounds: pixelRect(box, width: width, height: height)))
            }
            lines.append(RecognizedLine(text: text, bounds: lineBounds, words: words))
        }
        return lines.sorted { $0.bounds.minY < $1.bounds.minY }
    }

    /// The lines of text in `image`, top to bottom, for tasks and async functions: Vision runs on a queue of its own
    /// and the task's thread is free while it waits.
    public static func recognizeLines(in image: CGImage, language: String = "") async throws -> [RecognizedLine] {
        try await VisionQueue.run { try recognizeLines(in: image, language: language) }
    }

    /// All the text, one line per recognised line. Blocks the calling thread: only on a GCD queue or a thread of your
    /// own, never in a task or an async function (see `recognizeLines`).
    public static func recognizeText(in image: CGImage, language: String = "") throws -> String {
        try recognizeLines(in: image, language: language).map(\.text).joined(separator: "\n")
    }

    /// All the text, one line per recognised line, for tasks and async functions (the task's thread is free while
    /// Vision works).
    public static func recognizeText(in image: CGImage, language: String = "") async throws -> String {
        try await recognizeLines(in: image, language: language).map(\.text).joined(separator: "\n")
    }

    /// The languages Vision can recognise, as BCP 47 codes, for a settings popup.
    public static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// Vision's boxes are normalised with the origin at the bottom left; the editor's origin is the top left.
    static func pixelRect(_ normalized: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: normalized.minX * width, y: (1 - normalized.maxY) * height,
               width: normalized.width * width, height: normalized.height * height).integral
    }

    static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let s = start { ranges.append(s..<index); start = nil }
            } else if start == nil {
                start = index
            }
        }
        if let s = start { ranges.append(s..<text.endIndex) }
        return ranges
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// The text mode of the capture screen: which recognised line is under the mouse, and which words a dragged
/// rectangle selects, in reading order. Port of upstream `Greenshot/Capturing/Tools/TextCaptureTool.cs`.
/// The lines are in one coordinate space (the capture screen's Quartz global points).
public enum TextCaptureSelection {
    /// The lines in reading order: top to bottom, and left to right for lines on the same row (columns).
    public static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        let byTop = lines.sorted { $0.bounds.midY < $1.bounds.midY }
        var rows: [[RecognizedLine]] = []
        for line in byTop {
            // A line whose middle lies within the first line of the row belongs to that row.
            if let first = rows.last?.first, line.bounds.midY >= first.bounds.minY, line.bounds.midY <= first.bounds.maxY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    /// The line under `point`; the smallest one when lines overlap.
    public static func line(at point: CGPoint, in lines: [RecognizedLine]) -> RecognizedLine? {
        lines.filter { $0.bounds.contains(point) }.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// The words that `rect` touches, per line in reading order (lines without a selected word are left out).
    public static func selectedWords(in rect: CGRect, lines: [RecognizedLine]) -> [[RecognizedWord]] {
        guard rect.width > 0 || rect.height > 0 else { return [] }
        return readingOrder(lines).compactMap { line in
            guard line.bounds.intersects(rect) else { return nil }
            let words = line.words.filter { $0.bounds.intersects(rect) }.sorted { $0.bounds.minX < $1.bounds.minX }
            return words.isEmpty ? nil : words
        }
    }

    /// The selected words as text: the words of a line joined with spaces, the lines with line breaks.
    public static func text(in rect: CGRect, lines: [RecognizedLine]) -> String {
        selectedWords(in: rect, lines: lines).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// The lines of one display (pixels of its image, origin top left) moved to global points.
    public static func global(_ lines: [RecognizedLine], scale: CGFloat, origin: CGPoint) -> [RecognizedLine] {
        lines.map { line in
            RecognizedLine(text: line.text, bounds: Geometry.globalRect(fromPixels: line.bounds, scale: scale, origin: origin),
                           words: line.words.map {
                               RecognizedWord(text: $0.text, bounds: Geometry.globalRect(fromPixels: $0.bounds, scale: scale, origin: origin))
                           })
        }
    }
}

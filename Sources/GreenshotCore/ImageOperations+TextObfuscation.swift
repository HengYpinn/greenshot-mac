// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The search of upstream's text obfuscation (`Greenshot.Editor/Views/TextObfuscationWindow.xaml.cs`,
/// `TEXT_OBFUSCATION_FEATURE.md`): which recognized words or lines match the search, and the elements that cover
/// them. Kept apart from the text recognition so it can be tested without Vision.
public enum TextObfuscation {
    public enum SearchError: LocalizedError, Equatable {
        case invalidPattern(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPattern(let pattern): return String(localized: "“\(pattern)” is not a valid regular expression.")
            }
        }
    }

    /// The boxes (image pixels) of the words or lines (`settings.scope`) whose text matches `settings.searchPattern`,
    /// with the padding and offset of the settings applied and kept within `bounds` when given. An empty pattern
    /// matches all text. Throws `SearchError.invalidPattern` for a regular expression that does not compile.
    public static func matches(in lines: [RecognizedLine], settings: TextObfuscationSettings,
                               within bounds: CGRect? = nil) throws -> [CGRect] {
        let matcher = try Matcher(settings)
        let candidates: [(text: String, bounds: CGRect)]
        switch settings.scope {
        case .words: candidates = lines.flatMap { $0.words.map { ($0.text, $0.bounds) } }
        case .lines: candidates = lines.map { ($0.text, $0.bounds) }
        }
        return candidates.compactMap { candidate in
            guard matcher.matches(candidate.text) else { return nil }
            var box = padded(candidate.bounds, settings: settings)
            if let bounds { box = box.intersection(bounds) }
            return box.isNull || box.isEmpty ? nil : box
        }
    }

    /// Upstream `ApplyPadding`: the box grows by the padding percent of its size (half on each side), then moves by
    /// the offset in pixels.
    public static func padded(_ box: CGRect, settings: TextObfuscationSettings) -> CGRect {
        let horizontal: Double = Double(box.width) * Double(settings.paddingHorizontal) / 100 / 2
        let vertical: Double = Double(box.height) * Double(settings.paddingVertical) / 100 / 2
        let dx = CGFloat(Int(horizontal))
        let dy = CGFloat(Int(vertical))
        return CGRect(x: box.minX - dx + CGFloat(settings.offsetX), y: box.minY - dy + CGFloat(settings.offsetY),
                      width: box.width + dx * 2, height: box.height + dy * 2)
    }

    /// Upstream `CreateFilterContainer`: one obfuscate (pixelate, blur) or highlight (text, magnify) element per box,
    /// with the default style of its kind and the effect's options from the dialog (pixel size, blur radius,
    /// magnification, highlight color).
    public static func annotations(for boxes: [CGRect], settings: TextObfuscationSettings) -> [Annotation] {
        let kind: AnnotationKind = settings.effect == .pixelate || settings.effect == .blur ? .obfuscate : .highlight
        var style = AnnotationStyle.defaults(for: kind)
        switch settings.effect {
        case .pixelate:
            style.obfuscateMode = .pixelate
            style.pixelSize = Double(max(settings.pixelSize, 1))
        case .blur:
            style.obfuscateMode = .blur
            style.blurRadius = Double(max(settings.blurRadius, 1))
        case .highlight:
            style.highlightMode = .text
            style.fillColor = settings.highlightColor
        case .magnify:
            style.highlightMode = .magnify
            style.magnification = Double(max(settings.magnification, 1))
        }
        return boxes.map { box in
            Annotation(kind: kind, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY), style: style)
        }
    }

    /// Upstream `IsMatch`: a regular expression or plain text, with or without case.
    struct Matcher {
        private let pattern: String
        private let caseSensitive: Bool
        private let expression: NSRegularExpression?

        init(_ settings: TextObfuscationSettings) throws {
            pattern = settings.searchPattern
            caseSensitive = settings.caseSensitive
            if settings.useRegex && !pattern.isEmpty {
                do {
                    expression = try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
                } catch {
                    throw SearchError.invalidPattern(pattern)
                }
            } else {
                expression = nil
            }
        }

        func matches(_ text: String) -> Bool {
            guard !text.isEmpty else { return false }
            if pattern.isEmpty { return true }
            if let expression {
                return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
            return text.range(of: pattern, options: caseSensitive ? [] : [.caseInsensitive]) != nil
        }
    }
}

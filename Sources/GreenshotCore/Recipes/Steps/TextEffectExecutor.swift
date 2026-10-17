// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Upstream `TextEffectStep`: finds text with OCR (Vision), keeps the places that match the regular expressions of
/// `Patterns`, and covers them with an editable element: pixelize, blur, highlight, magnify or a filled rectangle
/// (Redact). Nothing found, no patterns or an OCR failure are logged and the flow goes on, like upstream.
struct TextEffectExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("TextEffectStep skipped: Payload is null.")
            return
        }
        let patterns = Self.patterns(step.value("Patterns"))
        guard !patterns.isEmpty else {
            log.warn("Recipe '\(context.recipe.id)': TextEffect has no patterns configured.")
            context.log("TextEffectStep skipped: no patterns configured.")
            return
        }
        let expressions = Self.compile(patterns, matchCase: step.bool("MatchCase") ?? false, context: context)
        guard !expressions.isEmpty else { return }
        context.log("Running OCR text detection for \(expressions.count) pattern(s)...")
        let lines: [RecognizedLine]
        do {
            let language = context.environment.configValue("ocrLanguage")?.asString ?? ""
            lines = try TextRecognizer.recognizeLines(in: payload.flattened() ?? payload.image, language: language)
        } catch {
            log.error("OCR of recipe '\(context.recipe.id)' failed during TextEffect.", error: error)
            context.log("Warning: OCR processing failed: \(error.localizedDescription)")
            return
        }
        guard !lines.isEmpty else {
            context.log("OCR detected no text content on surface.")
            return
        }
        let boxes = Self.matchedBounds(lines, expressions, scope: step.string("Scope") ?? "Auto",
                                       padding: Self.padding(step, scale: payload.scale))
        guard !boxes.isEmpty else {
            context.log("TextEffectStep found 0 pattern matches.")
            return
        }
        let effect = step.string("Effect") ?? "Pixelize"
        payload.annotations += boxes.map { Self.annotation(effect, box: $0, step) }
        context.payload = payload
        context.log("TextEffectStep applied '\(effect)' to \(boxes.count) matched region(s).")
    }

    /// The padding of the matched boxes: percent of their size (upstream defaults 10 and 20), and the offset in points
    /// turned into pixels (decision D2).
    struct Padding: Equatable {
        var horizontalPercent = 10
        var verticalPercent = 20
        var offset = CGVector.zero
    }

    static func padding(_ step: RecipeStepInvocation, scale: CGFloat) -> Padding {
        let all = step.int("Padding")
        var padding = Padding()
        padding.horizontalPercent = step.int("PaddingHorizontal") ?? all ?? 10
        padding.verticalPercent = step.int("PaddingVertical") ?? all ?? 20
        let dx = CGFloat(step.int("OffsetHorizontal") ?? 0) * scale
        let dy = CGFloat(step.int("OffsetVertical") ?? 0) * scale
        padding.offset = CGVector(dx: dx, dy: dy)
        return padding
    }

    /// `Patterns`: a list of regular expressions, or one as text; blanks and repeats left out.
    static func patterns(_ value: JSONValue?) -> [String] {
        let candidates: [String]
        switch value {
        case .array(let items): candidates = items.compactMap(\.asString)
        case .string(let text): candidates = [text]
        default: candidates = []
        }
        var result: [String] = []
        for pattern in candidates where !pattern.trimmingCharacters(in: .whitespaces).isEmpty && !result.contains(pattern) {
            result.append(pattern)
        }
        return result
    }

    private static func compile(_ patterns: [String], matchCase: Bool, context: RecipeFlowContext) -> [NSRegularExpression] {
        var expressions: [NSRegularExpression] = []
        for pattern in patterns {
            do {
                expressions.append(try NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive]))
            } catch {
                log.warn("Recipe '\(context.recipe.id)': invalid regex pattern '\(pattern)' in TextEffect.")
                context.log("Warning: Invalid regex pattern '\(pattern)': \(error.localizedDescription)")
            }
        }
        return expressions
    }

    /// Upstream `FindMatchedBounds`: whole lines (`Line`), single words (`Word`), or by default (`Auto`) the words a
    /// match overlaps within its line, the line when the match lies between the words.
    static func matchedBounds(_ lines: [RecognizedLine], _ expressions: [NSRegularExpression], scope: String,
                              padding: Padding) -> [CGRect] {
        func matches(_ text: String) -> Bool {
            expressions.contains { $0.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil }
        }
        if recipeEquals(scope, "Line") {
            return lines.filter { !$0.text.isEmpty && matches($0.text) }.map { padded($0.bounds, padding) }
        }
        if recipeEquals(scope, "Word") {
            return lines.flatMap(\.words).filter { !$0.text.isEmpty && matches($0.text) }.map { padded($0.bounds, padding) }
        }
        var results: [CGRect] = []
        for line in lines where !line.text.isEmpty && !line.words.isEmpty {
            let spans = wordSpans(line)
            let text = line.text as NSString
            for expression in expressions {
                for match in expression.matches(in: line.text, range: NSRange(location: 0, length: text.length)) {
                    let start = match.range.location
                    let end = match.range.location + match.range.length
                    let overlapping = spans.filter { $0.end > start && $0.start < end }.map(\.bounds)
                    if let first = overlapping.first {
                        results.append(padded(overlapping.dropFirst().reduce(first) { $0.union($1) }, padding))
                    } else {
                        results.append(padded(line.bounds, padding))
                    }
                }
            }
        }
        return results
    }

    /// Where each word sits in the line's text (UTF-16 offsets), searched from the end of the previous word first.
    private static func wordSpans(_ line: RecognizedLine) -> [(bounds: CGRect, start: Int, end: Int)] {
        let text = line.text as NSString
        var spans: [(bounds: CGRect, start: Int, end: Int)] = []
        var searchFrom = 0
        for word in line.words where !word.text.isEmpty {
            let length = (word.text as NSString).length
            var found = text.range(of: word.text, options: .caseInsensitive,
                                   range: NSRange(location: searchFrom, length: text.length - searchFrom))
            if found.location != NSNotFound {
                searchFrom = found.location + length
            } else {
                found = text.range(of: word.text, options: .caseInsensitive)
            }
            if found.location != NSNotFound {
                spans.append((word.bounds, found.location, found.location + length))
            }
        }
        return spans
    }

    /// Upstream `ApplyPadding`: half the percentage on each side (whole pixels), then the offset.
    static func padded(_ box: CGRect, _ padding: Padding) -> CGRect {
        let horizontal: Double = Double(box.width) * Double(padding.horizontalPercent) / 100 / 2
        let vertical: Double = Double(box.height) * Double(padding.verticalPercent) / 100 / 2
        let dx = CGFloat(Int(horizontal))
        let dy = CGFloat(Int(vertical))
        return CGRect(x: box.minX - dx + padding.offset.dx, y: box.minY - dy + padding.offset.dy,
                      width: box.width + dx * 2, height: box.height + dy * 2)
    }

    /// Upstream `CreateContainer`: the element of the effect over one box (image pixels).
    static func annotation(_ effect: String, box: CGRect, _ step: RecipeStepInvocation) -> Annotation {
        let kind: AnnotationKind
        var style: AnnotationStyle
        switch effect.lowercased() {
        case "blur":
            kind = .obfuscate
            style = .defaults(for: kind)
            style.obfuscateMode = .blur
            style.blurRadius = Double(max(step.int("BlurRadius") ?? 10, 1))
        case "highlight":
            kind = .highlight
            style = .defaults(for: kind)
            style.highlightMode = .text
            style.fillColor = step.color("FillColor") ?? .yellow
        case "magnify":
            kind = .highlight
            style = .defaults(for: kind)
            style.highlightMode = .magnify
            style.magnification = Double(max(step.int("MagnificationFactor") ?? 2, 1))
        case "redact":
            kind = .rectangle
            style = .defaults(for: kind)
            style.fillColor = step.color("FillColor") ?? .black
            style.lineColor = .clear
            style.lineWidth = 0
            style.shadow = false
        default:
            kind = .obfuscate
            style = .defaults(for: kind)
            style.obfuscateMode = .pixelate
            style.pixelSize = Double(max(step.int("PixelSize") ?? 5, 1))
        }
        return Annotation(kind: kind, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY), style: style)
    }
}

private let log = Log("Recipes")

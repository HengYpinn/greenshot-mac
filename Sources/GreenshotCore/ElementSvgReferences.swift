// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// What the references of an SVG add to drawing it, counted before macOS draws it. `<use>` draws the element it
/// points at again, a pattern draws its content for each shape painted with it, a mask for each shape it masks, and a
/// picture inside the SVG (a `data:` URL) can be an SVG itself. Chained ten at a time, a file of a kilobyte made macOS
/// draw a million rectangles, again at every redraw of an element showing it; `<use>` elements that draw each other
/// crashed it.
extension ElementSvg {
    /// The most elements the references of an SVG may add to it: far more than an icon sheet or a diagram repeats.
    static let maxReferencedElements = 50_000
    /// How deep SVG pictures inside SVG pictures may go.
    static let maxNestedPictures = 4

    /// Whether the references of `data` add at most `maxReferencedElements` elements and don't go round in a circle.
    /// False also when it isn't well-formed XML, which macOS doesn't draw either, when it declares entities, and when
    /// it was refused before (`refuse(_:)`).
    static func hasLimitedReferences(_ data: Data) -> Bool {
        drawnElements(data) != nil
    }

    /// The elements `data` draws with its references followed; nil when it is refused (see `hasLimitedReferences`).
    static func drawnElements(_ data: Data) -> Int? {
        let key = verdictKey(data)
        if let known = verdicts.object(forKey: key) { return known.intValue >= 0 ? known.intValue : nil }
        var drawn: Int?
        if case .counted(let written, let total) = SvgReferenceCount.count(data, depth: 0, known: SvgReferenceCount.Known()),
           total - written <= maxReferencedElements {
            drawn = total
        }
        verdicts.setObject(NSNumber(value: drawn ?? -1), forKey: key)
        return drawn
    }

    /// Refuses `data` from now on (an SVG that took too long to draw).
    static func refuse(_ data: Data) {
        verdicts.setObject(NSNumber(value: -1), forKey: verdictKey(data))
    }

    /// Whether `data` was counted or refused before and passed; nil when it wasn't.
    static func knownVerdict(_ data: Data) -> Bool? {
        verdicts.object(forKey: verdictKey(data)).map { $0.intValue >= 0 }
    }

    /// The count of each SVG, -1 for one refused, by the SHA-256 of its bytes: an element's SVG is looked at when it is
    /// read, laid out and drawn.
    private static let verdicts: NSCache<NSData, NSNumber> = {
        let cache = NSCache<NSData, NSNumber>()
        cache.countLimit = 512
        return cache
    }()

    private static func verdictKey(_ data: Data) -> NSData {
        Data(SHA256.hash(data: data)) as NSData
    }
}

/// One pass of `XMLParser` over an SVG (it never loads anything from outside the data), then the count.
private final class SvgReferenceCount: NSObject, XMLParserDelegate {
    struct Element {
        /// The element name without its prefix, in lower case (macOS takes `<USE>` for `<use>`).
        var name: String
        /// Its ids as written: every attribute named `id` (`id`, `xml:id`, any prefix), in any case.
        var ids: [String] = []
        var classes: [Substring]
        var parent: Int?
        var children: [Int] = []
        /// The element a `<use>` draws, or a pattern takes its content from (`href` or `xlink:href` as written, see
        /// `candidates(for:)`; macOS takes the last of the two, the parser doesn't say which that is).
        var draws: [String] = []
        /// The ids in the `url(#…)` of its attributes and of the style sheet rules for it.
        var paints: [String] = []
        /// The pictures inside it (`data:` URLs) and the elements they draw when they are SVG (counted after the
        /// parse: `XMLParser` can't parse another document while it parses one).
        var pictures: [Data] = []
        var nested = 0
    }

    private var elements: [Element] = []
    private var open: [Int] = []
    private var styleSheet = ""
    /// The document declares an entity: refused.
    private var hasEntities = false

    /// The counts of the inner pictures of one SVG by their bytes, so a picture that is there many times is counted
    /// once.
    final class Known {
        var counts: [Data: Count] = [:]
    }

    enum Count {
        /// The elements the document has, and those drawn with its references.
        case counted(written: Int, drawn: Int)
        /// It isn't well-formed XML (an inner picture of another format; macOS doesn't draw such an SVG either).
        case notXML
        /// Its references go round in a circle, or an inner picture is too deep or refused.
        case refused
    }

    static func count(_ data: Data, depth: Int, known: Known) -> Count {
        let counter = SvgReferenceCount()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = counter
        let parsed = parser.parse()
        guard !counter.hasEntities else { return .refused }
        guard parsed, !counter.elements.isEmpty else { return .notXML }
        // An SVG picture deeper than `maxNestedPictures` is refused, and nothing in it is looked at.
        guard depth <= ElementSvg.maxNestedPictures else { return .refused }
        var nested = 0
        for index in counter.elements.indices {
            // Whatever type a picture's URL says, macOS draws it as SVG when it is one: each one that is XML counts.
            for picture in counter.elements[index].pictures {
                let inner = known.counts[picture] ?? count(picture, depth: depth + 1, known: known)
                known.counts[picture] = inner
                switch inner {
                case .notXML:
                    continue
                case .counted(_, let drawn):
                    counter.elements[index].nested += drawn
                    nested += drawn
                    // Each one draws all of its elements more: past the limit already, the rest needn't be counted.
                    guard nested <= ElementSvg.maxReferencedElements else { return .refused }
                case .refused:
                    return .refused
                }
            }
        }
        guard counter.applyStyleSheet() else { return .refused }
        let limit = counter.elements.count + ElementSvg.maxReferencedElements
        guard let drawn = counter.drawnCount(limit: limit) else { return .refused }
        return .counted(written: counter.elements.count, drawn: drawn)
    }

    // MARK: Reading

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let name = Self.localName(elementName)
        var element = Element(name: name, classes: [], parent: open.last)
        for (key, value) in attributes {
            switch Self.localName(key) {
            case "id":
                element.ids.append(value)
            case "class":
                element.classes = value.split(whereSeparator: \.isWhitespace)
            case "href":
                let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let picture = Self.svgPicture(target) {
                    element.pictures.append(picture)
                } else if name == "use" || name == "pattern" {
                    element.draws.append(value)
                }
            default:
                break
            }
            element.paints += Self.urlReferences(in: value)
        }
        let index = elements.count
        elements.append(element)
        if let parent = open.last { elements[parent].children.append(index) }
        open.append(index)
    }

    /// Entities make the parser repeat text (an entity of an inner picture in thousands of attributes made counting
    /// take seconds); drawing programs don't write them.
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        hasEntities = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        hasEntities = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        open.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let current = open.last, elements[current].name == "style" { styleSheet += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let current = open.last, elements[current].name == "style" { styleSheet += String(decoding: CDATABlock, as: UTF8.self) }
    }

    /// The name without its prefix, in lower case.
    private static func localName(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name.lowercased() }
        return name[name.index(after: colon)...].lowercased()
    }

    /// The bytes of a `data:` URL (base64 or percent-encoded), whatever type it says; nil for anything else.
    private static func svgPicture(_ url: String) -> Data? {
        guard url.prefix(5).lowercased() == "data:", let comma = url.firstIndex(of: ",") else { return nil }
        let header = url[..<comma].lowercased()
        let payload = String(url[url.index(after: comma)...])
        if header.hasSuffix(";base64") {
            return Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters)
        }
        return (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    /// The ids of the `url(#id)` in `text` (an attribute or a style sheet rule).
    static func urlReferences(in text: String) -> [String] {
        guard text.contains("(") else { return [] }
        var ids: [String] = []
        var rest = text[...]
        while let found = rest.range(of: "url(", options: .caseInsensitive) {
            rest = rest[found.upperBound...].drop { $0.isWhitespace || $0 == "\"" || $0 == "'" }
            guard rest.first == "#" else { continue }
            let id = rest.dropFirst().prefix { !$0.isWhitespace && $0 != ")" && $0 != "\"" && $0 != "'" }
            if !id.isEmpty { ids.append(String(id)) }
        }
        return ids
    }

    /// The elements with each id, as written and without the white space around it.
    private var byID: [String: [Int]] {
        var byID: [String: [Int]] = [:]
        for (index, element) in elements.enumerated() {
            for id in element.ids {
                byID[id, default: []].append(index)
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != id { byID[trimmed, default: []].append(index) }
            }
        }
        return byID
    }

    /// The most elements one reference may stand for (one id written for several elements, or spelled alike).
    private static let maxCandidates = 16

    /// The elements `reference` (an `href` or the id of a `url(#…)`) may stand for: macOS takes the text after the
    /// first "#" and the id as written, this counter also the text after the last "#" and either without white space
    /// around, and counts the biggest of them. Nil when they are more than `maxCandidates`.
    private static func candidates(for reference: String, in byID: [String: [Int]]) -> [Int]? {
        var spellings: Set<String> = []
        for text in [reference, reference.trimmingCharacters(in: .whitespacesAndNewlines)] {
            spellings.insert(text)
            if let first = text.firstIndex(of: "#") { spellings.insert(String(text[text.index(after: first)...])) }
            if let last = text.lastIndex(of: "#") { spellings.insert(String(text[text.index(after: last)...])) }
        }
        var found: [Int] = []
        for spelling in spellings {
            for index in byID[spelling] ?? [] where !found.contains(index) {
                found.append(index)
                if found.count > maxCandidates { return nil }
            }
        }
        return found
    }

    /// Adds the patterns and masks in the `url(#…)` of each style sheet rule to the elements the rule is for: by a
    /// class, an id or an element name, all elements for any other selector. False when that adds more references than
    /// `maxReferencedElements` (each one draws at least one element more).
    private func applyStyleSheet() -> Bool {
        guard styleSheet.contains("url") else { return true }
        let byID = byID
        // Without the comments, in one pass.
        var text = ""
        var rest = styleSheet[...]
        while let start = rest.range(of: "/*") {
            text += rest[..<start.lowerBound]
            rest = rest[start.upperBound...]
            rest = rest.range(of: "*/").map { rest[$0.upperBound...] } ?? ""
        }
        text += rest
        func isWord(_ text: Substring) -> Bool {
            !text.isEmpty && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
        // The ids of each selector, gathered first: every rule going over every element took minutes.
        var everywhere = Set<String>()
        var byClass: [Substring: Set<String>] = [:]
        var byElementID: [Substring: Set<String>] = [:]
        var byName: [Substring: Set<String>] = [:]
        for rule in text.split(separator: "}") {
            guard let brace = rule.firstIndex(of: "{") else { continue }
            let ids = Self.urlReferences(in: String(rule[rule.index(after: brace)...])).filter { id in
                (Self.candidates(for: id, in: byID) ?? [0]).contains { Self.expanding.contains(elements[$0].name) }
            }
            guard !ids.isEmpty else { continue }
            for selector in rule[..<brace].split(separator: ",") {
                let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)[...]
                let name = selector.dropFirst()
                if selector.first == ".", isWord(name) {
                    byClass[name, default: []].formUnion(ids)
                } else if selector.first == "#", isWord(name) {
                    byElementID[name, default: []].formUnion(ids)
                } else if isWord(selector) {
                    byName[selector.lowercased()[...], default: []].formUnion(ids)
                } else {
                    everywhere.formUnion(ids)
                }
            }
        }
        var added = 0
        for index in elements.indices {
            let element = elements[index]
            var ids = everywhere.union(byName[element.name[...]] ?? [])
            for id in element.ids {
                ids.formUnion(byElementID[id[...]] ?? [])
                ids.formUnion(byElementID[id.trimmingCharacters(in: .whitespacesAndNewlines)[...]] ?? [])
            }
            for name in element.classes { ids.formUnion(byClass[name] ?? []) }
            added += ids.count
            guard added <= ElementSvg.maxReferencedElements else { return false }
            elements[index].paints += ids
        }
        return true
    }

    /// The elements whose content is drawn again for each element that paints with them.
    private static let expanding: Set<String> = ["pattern", "mask"]

    // MARK: Counting

    /// The elements drawn from the root with every reference followed (at least `limit` + 1 when that is more); nil
    /// for references in a circle.
    private func drawnCount(limit: Int) -> Int? {
        let byID = byID
        /// Whether `index` is `ancestor` or inside it.
        func isWithin(_ index: Int, _ ancestor: Int) -> Bool {
            var current: Int? = index
            while let at = current {
                if at == ancestor { return true }
                current = elements[at].parent
            }
            return false
        }
        /// What element `index` draws: its children, and for each reference the elements it may stand for, of which
        /// the biggest counts. Nil when a reference stands for too many.
        func references(of index: Int) -> (children: [Int], choices: [[Int]])? {
            let element = elements[index]
            var choices: [[Int]] = []
            for reference in element.draws {
                guard let found = Self.candidates(for: reference, in: byID) else { return nil }
                if !found.isEmpty { choices.append(found) }
            }
            for reference in element.paints {
                // Painting an element with itself or with a pattern or mask it is in is skipped when it is drawn (a
                // style sheet rule for every element reaches the pattern's own content too); only other circles are
                // refused.
                guard let found = Self.candidates(for: reference, in: byID) else { return nil }
                let painting = found.filter { Self.expanding.contains(elements[$0].name) && !isWithin(index, $0) }
                if !painting.isEmpty { choices.append(painting) }
            }
            return (element.children, choices)
        }
        // Depth first without recursion (a chain of references can be as long as the file): an element is counted
        // when everything it draws is.
        var drawn = [Int?](repeating: nil, count: elements.count)
        var visiting = [Bool](repeating: false, count: elements.count)
        var stack: [(index: Int, children: [Int], choices: [[Int]], targets: [Int], next: Int)] = []
        func push(_ index: Int) -> Bool {
            guard let found = references(of: index) else { return false }
            visiting[index] = true
            stack.append((index, found.children, found.choices, found.children + found.choices.flatMap { $0 }, 0))
            return true
        }
        for root in elements.indices where drawn[root] == nil {
            guard push(root) else { return nil }
            while let top = stack.last {
                if top.next < top.targets.count {
                    let target = top.targets[top.next]
                    stack[stack.count - 1].next += 1
                    guard drawn[target] == nil else { continue }
                    // Reached again before it was counted: it draws itself.
                    guard !visiting[target], push(target) else { return nil }
                    continue
                }
                stack.removeLast()
                visiting[top.index] = false
                var total = 1 + elements[top.index].nested
                for child in top.children { total = min(total + (drawn[child] ?? 0), limit + 1) }
                for choice in top.choices {
                    total = min(total + (choice.compactMap { drawn[$0] }.max() ?? 0), limit + 1)
                }
                drawn[top.index] = total
            }
        }
        return drawn[0]
    }
}

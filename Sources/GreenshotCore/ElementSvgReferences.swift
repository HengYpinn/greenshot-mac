// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

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
    /// False also when it isn't well-formed XML, which macOS doesn't draw either.
    static func hasLimitedReferences(_ data: Data) -> Bool {
        guard let counts = SvgReferenceCount.count(data, depth: 0) else { return false }
        return counts.drawn - counts.written <= maxReferencedElements
    }
}

/// One pass of `XMLParser` over an SVG (it never loads anything from outside the data), then the count.
private final class SvgReferenceCount: NSObject, XMLParserDelegate {
    struct Element {
        var name: String
        var id: String?
        var classes: [Substring]
        var children: [Int] = []
        /// The element a `<use>` draws, or a pattern takes its content from (`href`, by id).
        var draws: String?
        /// The ids in the `url(#…)` of its attributes and of the style sheet rules for it.
        var paints: [String] = []
        /// The SVG pictures inside it, and the elements they draw (counted after the parse: `XMLParser` can't parse
        /// another document while it parses one).
        var pictures: [Data] = []
        var nested = 0
    }

    private var elements: [Element] = []
    private var open: [Int] = []
    private var styleSheet = ""

    /// The elements `data` has (`written`) and those drawn with its references (`drawn`); nil when the references go
    /// round in a circle, an inner picture is too deep or too big, or `data` isn't well-formed XML.
    static func count(_ data: Data, depth: Int) -> (written: Int, drawn: Int)? {
        let counter = SvgReferenceCount()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = counter
        guard parser.parse(), !counter.elements.isEmpty else { return nil }
        for index in counter.elements.indices {
            for picture in counter.elements[index].pictures {
                guard depth < ElementSvg.maxNestedPictures, let inner = count(picture, depth: depth + 1) else { return nil }
                counter.elements[index].nested += inner.drawn
            }
        }
        counter.applyStyleSheet()
        let limit = counter.elements.count + ElementSvg.maxReferencedElements
        guard let drawn = counter.drawnCount(limit: limit) else { return nil }
        return (counter.elements.count, drawn)
    }

    // MARK: Reading

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let name = Self.localName(elementName)
        var element = Element(name: name, classes: [])
        for (key, value) in attributes {
            switch Self.localName(key) {
            case "id" where key == "id":
                element.id = value.trimmingCharacters(in: .whitespaces)
            case "class":
                element.classes = value.split(whereSeparator: \.isWhitespace)
            case "href":
                let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if target.hasPrefix("#"), name == "use" || name == "pattern" {
                    element.draws = String(target.dropFirst())
                } else if let picture = Self.svgPicture(target) {
                    element.pictures.append(picture)
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

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        open.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let current = open.last, elements[current].name == "style" { styleSheet += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let current = open.last, elements[current].name == "style" { styleSheet += String(decoding: CDATABlock, as: UTF8.self) }
    }

    private static func localName(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    /// The SVG in a `data:` URL (base64 or percent-encoded) that says it is one or looks like one; nil for anything else.
    private static func svgPicture(_ url: String) -> Data? {
        guard url.prefix(5).lowercased() == "data:", let comma = url.firstIndex(of: ",") else { return nil }
        let header = url[..<comma].lowercased()
        let payload = String(url[url.index(after: comma)...])
        let data = header.hasSuffix(";base64")
            ? Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters)
            : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
        return data.flatMap { header.contains("svg") || ElementSvg.isSVG($0) ? $0 : nil }
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

    /// Adds the `url(#…)` of each style sheet rule to the elements it is for: by a class, an id or an element name,
    /// all elements for any other selector.
    private func applyStyleSheet() {
        guard styleSheet.contains("url") else { return }
        var text = styleSheet
        while let start = text.range(of: "/*") {
            let end = text.range(of: "*/", range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
            text.removeSubrange(start.lowerBound..<end)
        }
        for rule in text.split(separator: "}") {
            guard let brace = rule.firstIndex(of: "{") else { continue }
            let ids = Self.urlReferences(in: String(rule[rule.index(after: brace)...]))
            guard !ids.isEmpty else { continue }
            for selector in rule[..<brace].split(separator: ",") {
                let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
                let isName = selector.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                for index in elements.indices where Self.matches(selector, isName: isName, elements[index]) {
                    elements[index].paints += ids
                }
            }
        }
    }

    private static func matches(_ selector: String, isName: Bool, _ element: Element) -> Bool {
        let name = selector.dropFirst()
        let isSimple = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        if selector.hasPrefix("."), isSimple { return element.classes.contains(name) }
        if selector.hasPrefix("#"), isSimple { return element.id.map { $0[...] == name } ?? false }
        if isName, !selector.isEmpty { return element.name == selector }
        return true
    }

    // MARK: Counting

    /// The elements drawn from the root with every reference followed (at least `limit` + 1 when that is more); nil
    /// for references in a circle.
    private func drawnCount(limit: Int) -> Int? {
        var byID: [String: [Int]] = [:]
        for (index, element) in elements.enumerated() {
            if let id = element.id { byID[id, default: []].append(index) }
        }
        let expands: Set<String> = ["pattern", "mask"]
        func references(of element: Element) -> [Int] {
            var targets = element.children
            if let draws = element.draws { targets += byID[draws] ?? [] }
            for id in element.paints {
                targets += (byID[id] ?? []).filter { expands.contains(elements[$0].name) }
            }
            return targets
        }
        // Depth first without recursion (a chain of references can be as long as the file): an element is counted
        // when everything it draws is.
        var drawn = [Int?](repeating: nil, count: elements.count)
        var visiting = [Bool](repeating: false, count: elements.count)
        var stack: [(index: Int, targets: [Int], next: Int)] = []
        for root in elements.indices where drawn[root] == nil {
            visiting[root] = true
            stack.append((root, references(of: elements[root]), 0))
            while let top = stack.last {
                if top.next < top.targets.count {
                    let target = top.targets[top.next]
                    stack[stack.count - 1].next += 1
                    guard drawn[target] == nil else { continue }
                    // Reached again before it was counted: it draws itself.
                    guard !visiting[target] else { return nil }
                    visiting[target] = true
                    stack.append((target, references(of: elements[target]), 0))
                    continue
                }
                stack.removeLast()
                visiting[top.index] = false
                var total = 1 + elements[top.index].nested
                for target in top.targets { total = min(total + (drawn[target] ?? 0), limit + 1) }
                drawn[top.index] = total
            }
        }
        return drawn[0]
    }
}

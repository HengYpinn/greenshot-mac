// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Turns the elements of Greenshot for Windows files (`.greenshot`, `.gst` templates) into elements of this editor, the
/// way upstream's `LegacyToDocument` maps them (branch commit 7165e4ad) and with the defaults of the containers'
/// `InitializeFields`. Positions are image pixels on both sides; sizes stored in pixels (line thickness, pixel size,
/// blur radius, teeth, font size: upstream's fonts are `GraphicsUnit.Pixel`) become points of the image's scale.
/// Not kept: the rotation of emoji, SVG and metafile elements, and anything of an element type that isn't known here.
enum GreenshotLegacyImport {
    struct Result {
        var elements: [Annotation]
        /// The number of the first counter (upstream `StepLabelContainer._counterStart`), 1 without counters.
        var counterStart: Int
        /// What could not be shown, by kind, in file order.
        var unreadable: [String]
    }

    /// The elements of a BinaryFormatter stream (a `.gst` file or the element part of a `.greenshot` file) for an image
    /// with `scale` pixels per point.
    static func read(payload: Data, scale: CGFloat) throws -> Result {
        convert(try GreenshotLegacyReader.elements(fromPayload: payload), scale: scale)
    }

    static func convert(_ legacy: [LegacyElement], scale: CGFloat) -> Result {
        var elements: [Annotation] = []
        var unreadable: [String] = []
        var numbers: [UUID: Int] = [:]
        var counterStart: Int?
        for element in legacy {
            guard let annotation = annotation(element, scale: max(scale, 1)) else {
                unreadable.append(displayName(of: element))
                continue
            }
            if case .stepLabel(let number, let start) = element.content {
                numbers[annotation.id] = number
                if counterStart == nil { counterStart = start }
            }
            elements.append(annotation)
        }
        return Result(elements: numbered(elements, numbers), counterStart: max(counterStart ?? 1, 0), unreadable: unreadable)
    }

    /// The counters in the places counters have, in the order of their numbers: this editor numbers them in drawing
    /// order, upstream sorts them by number (`Surface.LoadElementsFromStream` sorts `_stepLabels`).
    private static func numbered(_ elements: [Annotation], _ numbers: [UUID: Int]) -> [Annotation] {
        let slots = elements.indices.filter { elements[$0].kind == .counter }
        let sorted = slots.map { elements[$0] }.enumerated().sorted { a, b in
            let left = numbers[a.element.id] ?? 0
            let right = numbers[b.element.id] ?? 0
            return left == right ? a.offset < b.offset : left < right
        }
        var result = elements
        for (slot, counter) in zip(slots, sorted) { result[slot] = counter.element }
        return result
    }

    /// The element as this editor has it; nil when it can't be shown here.
    static func annotation(_ element: LegacyElement, scale: CGFloat) -> Annotation? {
        guard let kind = kind(of: element.typeName) else { return nil }
        let start = CGPoint(x: element.left, y: element.top)
        let end = CGPoint(x: element.left + element.width, y: element.top + element.height)
        var annotation = Annotation(kind: kind, start: start, end: end, style: style(element, kind: kind, scale: scale))
        switch element.content {
        case .none:
            break
        case .text(let text):
            annotation.text = text
        case .speechBubble(let text, let target):
            annotation.text = text
            annotation.tail = target
        case .stepLabel:
            break
        case .freehand(let points):
            let moved = points.map { CGPoint(x: $0.x + start.x, y: $0.y + start.y) }
            guard let first = moved.first, let last = moved.last else { return nil }
            annotation.points = moved
            annotation.start = first
            annotation.end = last
        case .picture(let data, _):
            guard let png = pngData(data) else { return nil }
            annotation.imageData = png
        case .svg(let data, _):
            guard let data, !data.isEmpty else { return nil }
            annotation.imageData = data
        case .emoji(let emoji, _):
            guard !emoji.isEmpty else { return nil }
            annotation.text = emoji
        case .cursor(let data):
            guard let png = pngData(data) else { return nil }
            annotation.imageData = png
        case .cutMark(let horizontal, let seed, let shadow):
            annotation.verticalCut = !horizontal
            annotation.seed = UInt64(bitPattern: Int64(seed))
            annotation.cutEdges = layout(shadow)
        case .tornEdge(let seed, let edges, let margins, let shadow):
            annotation.seed = UInt64(bitPattern: Int64(seed))
            var layout = layout(shadow) ?? CutEdgeLayout()
            if let edges, edges.count == 4 {
                (layout.top, layout.right, layout.bottom, layout.left) = (edges[0], edges[1], edges[2], edges[3])
            }
            if let margins, margins.count == 4 {
                let limited = margins.map { min(max($0, 0), 4000) }
                (layout.marginTop, layout.marginRight, layout.marginBottom, layout.marginLeft) = (limited[0], limited[1], limited[2], limited[3])
            }
            annotation.cutEdges = layout
        }
        return annotation
    }

    private static func kind(of typeName: String) -> AnnotationKind? {
        switch typeName {
        case "RectangleContainer": return .rectangle
        case "EllipseContainer": return .ellipse
        case "LineContainer": return .line
        case "ArrowContainer": return .arrow
        case "TextContainer": return .text
        case "SpeechbubbleContainer": return .speechBubble
        case "StepLabelContainer": return .counter
        case "FreehandContainer": return .freehand
        case "HighlightContainer": return .highlight
        case "ObfuscateContainer": return .obfuscate
        case "ImageContainer", "IconContainer", "MetafileContainer", "BarcodeContainer": return .image
        case "SvgContainer": return .svg
        case "EmojiContainer": return .emoji
        case "CursorContainer": return .cursor
        case "CutMarkContainer": return .cutMark
        case "TornEdgeContainer": return .tornEdge
        default: return nil
        }
    }

    /// How an element that can't be shown is named in the editor's message.
    static func displayName(of element: LegacyElement) -> String {
        switch element.typeName {
        case "CursorContainer": return "mouse pointer of Greenshot 1.3"
        case "SvgContainer": return "SVG picture"
        case "ImageContainer", "IconContainer", "MetafileContainer", "BarcodeContainer": return "picture"
        case "FreehandContainer": return "empty freehand line"
        case "EmojiContainer": return "emoji"
        default:
            let name = element.typeName.hasSuffix("Container") ? String(element.typeName.dropLast("Container".count)) : element.typeName
            return name.isEmpty ? "unknown element" : name
        }
    }

    // MARK: Style

    /// The fields of the element as a style; what it doesn't have keeps this editor's default for the kind.
    static func style(_ element: LegacyElement, kind: AnnotationKind, scale: CGFloat) -> AnnotationStyle {
        var style = AnnotationStyle.defaults(for: kind)
        let pixelsPerPoint = Double(scale)
        func points(_ name: String, _ range: ClosedRange<Double>) -> Double? {
            guard let pixels = element.field(name)?.number, pixels.isFinite else { return nil }
            return min(max(pixels / pixelsPerPoint, range.lowerBound), range.upperBound)
        }
        func number(_ name: String) -> Int? {
            guard let value = element.field(name)?.number, value.isFinite else { return nil }
            return Int(min(max(value, -1_000_000), 1_000_000))
        }
        if case .color(let color)? = element.field("LINE_COLOR") { style.lineColor = rgba(color) }
        if case .color(let color)? = element.field("FILL_COLOR") { style.fillColor = rgba(color) }
        if let width = points("LINE_THICKNESS", 0...100) { style.lineWidth = width }
        if case .bool(let shadow)? = element.field("SHADOW") { style.shadow = shadow }
        if case .string(let family)? = element.field("FONT_FAMILY") { style.fontFamily = family }
        if let size = points("FONT_SIZE", 1...500) { style.fontSize = size }
        if case .bool(let bold)? = element.field("FONT_BOLD") { style.bold = bold }
        if case .bool(let italic)? = element.field("FONT_ITALIC") { style.italic = italic }
        if let alignment = number("TEXT_HORIZONTAL_ALIGNMENT") {
            // StringAlignment Near, Center, Far.
            style.horizontalAlignment = alignment == 0 ? .left : alignment == 2 ? .right : .center
        }
        if let alignment = number("TEXT_VERTICAL_ALIGNMENT") {
            style.verticalAlignment = alignment == 0 ? .top : alignment == 2 ? .bottom : .center
        }
        if let heads = number("ARROWHEADS"), ArrowHeads.allCases.indices.contains(heads) {
            // ArrowHeadCombination NONE, START_POINT, END_POINT, BOTH: the same order.
            style.arrowHeads = ArrowHeads.allCases[heads]
        }
        // FilterContainer.PreparedFilter: BLUR, PIXELIZE, TEXT_HIGHTLIGHT, AREA_HIGHLIGHT, GRAYSCALE, MAGNIFICATION.
        if let filter = number("PREPARED_FILTER_HIGHLIGHT") {
            let modes: [Int: HighlightMode] = [2: .text, 3: .area, 4: .grayscale, 5: .magnify]
            style.highlightMode = modes[filter] ?? .text
        }
        if let filter = number("PREPARED_FILTER_OBFUSCATE") {
            style.obfuscateMode = filter == 0 ? .blur : .pixelate
        }
        if let size = points("PIXEL_SIZE", 1...100) { style.pixelSize = size }
        if let radius = points("BLUR_RADIUS", 0...100) { style.blurRadius = radius }
        if let brightness = element.field("BRIGHTNESS")?.number, brightness.isFinite { style.brightness = min(max(brightness, 0), 2) }
        if let factor = number("MAGNIFICATION_FACTOR") { style.magnification = Double(min(max(factor, 1), 8)) }
        if let cut = number("CUT_MARK_STYLE"), CutMarkStyle.allCases.indices.contains(cut) {
            // CutMarkStyle None, Line, ZigZag, Wave, Torn: the same order.
            style.cutMarkStyle = CutMarkStyle.allCases[cut]
        }
        if let height = points("TOOTH_HEIGHT", 1...100) { style.toothHeight = height }
        if let range = points("TOOTH_RANGE", 2...500) { style.toothRange = range }
        return style
    }

    /// The color, from its ARGB value, its known color number or its name; clear when it has none of them.
    static func rgba(_ color: LegacyColor) -> RGBAColor {
        let argb: UInt32?
        if color.isArgb {
            argb = UInt32(truncatingIfNeeded: color.value)
        } else if color.isKnownColor {
            argb = LegacyKnownColors.argb(knownColor: color.knownColor)
        } else if color.isNamedColor, let name = color.name {
            argb = LegacyKnownColors.argb(named: name)
        } else {
            argb = nil
        }
        guard let argb else { return .clear }
        let alpha = Double(argb >> 24 & 0xFF) / 255
        let red = Double(argb >> 16 & 0xFF) / 255
        let green = Double(argb >> 8 & 0xFF) / 255
        let blue = Double(argb & 0xFF) / 255
        return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// The shadow of a cut mark or torn edges; nil when the file has none (the effect's defaults then).
    private static func layout(_ shadow: LegacyElement.LegacyShadow) -> CutEdgeLayout? {
        guard shadow.size > 0 else { return nil }
        let darkness = shadow.darkness.isFinite ? min(max(shadow.darkness, 0), 1) : 0.6
        return CutEdgeLayout(shadowDarkness: darkness, shadowSize: min(max(shadow.size, 1), 20),
                             shadowOffsetX: min(max(shadow.offsetX, -20), 20), shadowOffsetY: min(max(shadow.offsetY, -20), 20))
    }

    /// The picture as PNG: PNG stays, other formats this Mac reads (the ICO of an icon element) are converted, the
    /// biggest icon size first.
    static func pngData(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        guard let loaded = ImageFileLoader.load(data: data) else { return nil }
        return try? ImageExporter.data(for: loaded.image, format: .png, scale: loaded.scale)
    }
}

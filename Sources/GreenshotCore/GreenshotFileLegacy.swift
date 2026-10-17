// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A field (property) of an element of Greenshot for Windows, e.g. LINE_THICKNESS = 2 (upstream
/// `Greenshot.Editor/Drawing/Fields/Field.cs`).
struct LegacyField: Equatable {
    var name: String
    var value: LegacyValue
}

/// The value of a field as it was stored.
enum LegacyValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case color(LegacyColor)
    /// An enum, e.g. StringAlignment, ArrowHeadCombination, FilterContainer+PreparedFilter, CutMarkStyle.
    case enumeration(type: String, value: Int64)
    case unsupported(String)

    var number: Double? {
        switch self {
        case .number(let value): return value
        case .enumeration(_, let value): return Double(value)
        default: return nil
        }
    }
}

/// A System.Drawing.Color as it was serialized: an ARGB value, a known color or a named one.
struct LegacyColor: Equatable {
    var value: Int64
    var knownColor: Int
    var state: Int
    var name: String?

    var isKnownColor: Bool { state & 0x0001 != 0 }
    var isArgb: Bool { state & 0x0002 != 0 }
    var isNamedColor: Bool { state & 0x0008 != 0 }
}

/// A filter of a highlight or obfuscate element (upstream `Drawing/Filters/*Filter.cs`), with its own fields.
struct LegacyFilter: Equatable {
    var name: String
    var fields: [LegacyField]
}

/// An element (drawable container) of Greenshot for Windows 1.2 - 1.4 and later, as stored in `.greenshot` and `.gst`
/// files; port of `LegacyElement` of upstream's BinaryFormatter-free reader (branch commit 7165e4ad).
struct LegacyElement: Equatable {
    /// The class name without namespace, e.g. "RectangleContainer".
    var typeName: String
    var left: Int
    var top: Int
    var width: Int
    var height: Int
    var fields: [LegacyField] = []
    var filters: [LegacyFilter] = []
    var content: Content = .none

    /// What some kinds keep besides their box and fields.
    enum Content: Equatable {
        case none
        case text(String)
        /// Text and where the tail points (`_storedTargetGripperLocation`, image pixels).
        case speechBubble(text: String, target: CGPoint?)
        case stepLabel(number: Int, counterStart: Int)
        /// The path, relative to left, top (upstream draws it with `TranslateTransform(Left, Top)`).
        case freehand([CGPoint])
        /// Image, icon, metafile: the picture's file (PNG, or ICO for icons).
        case picture(Data?, rotation: Int)
        /// A barcode (`BarcodeContainer`): its picture, and what it shows when the file has it (`_model`, upstream's
        /// `ZxingModel`) with the quiet zone (`_margin`).
        case barcode(picture: Data?, model: LegacyBarcodeModel?, margin: Int?)
        case svg(Data?, rotation: Int)
        case emoji(String, rotation: Int)
        /// The pointer's color layer (PNG); Greenshot 1.3 stored a cursor that can't be read, then it is nil.
        case cursor(Data?)
        case cutMark(horizontal: Bool, seed: Int, shadow: LegacyShadow)
        case tornEdge(seed: Int, edges: [Bool]?, margins: [Int]?, shadow: LegacyShadow)
    }

    /// What a barcode shows: the auto properties of upstream's `ZxingModel` (`Greenshot.Plugin.Zxing/Drawing/ZxingModel.cs`).
    struct LegacyBarcodeModel: Equatable {
        /// `FormatIndex`, `QrCategoryIndex`, `WifiEncryptionIndex`: positions in the dialog's lists.
        var formatIndex = 0
        var qrCategoryIndex = 0
        var wifiEncryptionIndex = 0
        /// The text properties by name ("RawText", "WifiSsid", …); a property that was null is missing.
        var texts: [String: String] = [:]
        var foreColor: LegacyColor?
        var backColor: LegacyColor?
        var roundedDots = false
        var margin: Int?

        /// The names of the text properties.
        static let textNames = ["RawText", "WifiSsid", "WifiPassword", "VcardFirstName", "VcardLastName", "VcardPhone",
                                "VcardEmail", "VcardCompany", "VcardUrl", "EpcName", "EpcIban", "EpcBic", "EpcAmount",
                                "EpcReference", "EpcMessage", "EmailTo", "EmailSubject", "EmailBody", "EventTitle",
                                "EventLocation", "EventStart", "EventEnd", "EventDescription", "PhoneNumber", "SmsNumber",
                                "SmsMessage", "Latitude", "Longitude"]
    }

    /// The shadow settings of cut marks and torn edges (`_shadowDarkness`, `_shadowSize`, `_shadowOffsetX/Y`).
    struct LegacyShadow: Equatable {
        var darkness: Double
        var size: Int
        var offsetX: Int
        var offsetY: Int
    }

    /// The value of a field of the element, or else of one of its filters (a highlight's color is its filter's).
    func field(_ name: String) -> LegacyValue? {
        if let field = fields.first(where: { $0.name == name }) { return field.value }
        for filter in filters {
            if let field = filter.fields.first(where: { $0.name == name }) { return field.value }
        }
        return nil
    }
}

/// Reads the elements of a BinaryFormatter stream of Greenshot for Windows (a `.gst` file, or the part of a `.greenshot`
/// file after the PNG). Members are looked up by the names of the Greenshot 1.2 - 1.4 classes; nothing is created from
/// a type name, a foreign type only becomes an element of an unknown kind.
enum GreenshotLegacyReader {
    /// At most this many elements are read.
    static let maxElements = 10_000

    static func elements(fromPayload data: Data) throws -> [LegacyElement] {
        let graph = try NRBFDecoder.decode(data)
        guard let list = graph.instance(graph.root) else { throw NRBFError.notNRBF }
        return listItems(list, in: graph).prefix(maxElements).compactMap { item in
            graph.instance(item).map { element($0, in: graph) }
        }
    }

    private static func element(_ record: NRBFInstance, in graph: NRBFGraph) -> LegacyElement {
        var element = LegacyElement(typeName: record.simpleName, left: int(record, "left", graph), top: int(record, "top", graph),
                                    width: int(record, "width", graph), height: int(record, "height", graph))
        element.fields = fields(of: record, in: graph)
        element.filters = listItems(graph.instance(record.member("Children")), in: graph).compactMap { child in
            graph.instance(child).map { LegacyFilter(name: $0.simpleName, fields: fields(of: $0, in: graph)) }
        }
        element.content = content(of: record, in: graph)
        return element
    }

    private static func content(of record: NRBFInstance, in graph: NRBFGraph) -> LegacyElement.Content {
        func text(_ name: String) -> String { graph.string(record.member(name)) ?? "" }
        func number(_ name: String, _ fallback: Int = 0) -> Int { int(record, name, graph, fallback) }
        switch record.simpleName {
        case "TextContainer":
            return .text(text("text"))
        case "SpeechbubbleContainer":
            let target = graph.instance(record.member("_storedTargetGripperLocation")).map { point($0, graph) }
            return .speechBubble(text: text("text"), target: target)
        case "StepLabelContainer":
            return .stepLabel(number: number("_number"), counterStart: number("_counterStart", 1))
        case "FreehandContainer":
            let points = listItems(graph.instance(record.member("capturePoints")), in: graph)
                .compactMap { graph.instance($0).map { point($0, graph) } }
            return .freehand(points)
        case "ImageContainer":
            return .picture(picture(of: record, graph), rotation: 0)
        case "BarcodeContainer":
            let model = graph.instance(record.member("_model")).map { barcodeModel($0, graph) }
            return .barcode(picture: picture(of: record, graph), model: model, margin: intValue(record.member("_margin")))
        case "IconContainer":
            return .picture(graph.instance(record.member("icon")).flatMap { graph.bytes($0.member("IconData")) }, rotation: 0)
        case "MetafileContainer":
            let metafile = graph.instance(record.member("_metafile"))
            return .picture(metafile.flatMap { graph.bytes($0.member("Data")) }, rotation: number("_rotationAngle"))
        case "SvgContainer":
            return .svg(memoryStream(graph.instance(record.member("_svgContent")), graph), rotation: number("_rotationAngle"))
        case "EmojiContainer":
            return .emoji(text("_emoji"), rotation: number("_rotationAngle"))
        case "CursorContainer":
            // 1.3 stored a System.Windows.Forms.Cursor (which 1.3 could not read back either), 1.4 a wrapper with layers.
            let wrapper = graph.instance(record.member("savedCursor"))
            return .cursor(wrapper.flatMap { graph.instance($0.member("ColorLayer")) }.flatMap { graph.bytes($0.member("Data")) })
        case "CutMarkContainer":
            return .cutMark(horizontal: bool(record.member("_horizontal")), seed: number("_seed"), shadow: shadow(record, graph))
        case "TornEdgeContainer":
            let edges = graph.array(record.member("_edges"))?.map { bool($0) }
            let margins = graph.array(record.member("_margins"))?.map { intValue($0) ?? 0 }
            return .tornEdge(seed: number("_seed"), edges: edges, margins: margins, shadow: shadow(record, graph))
        default:
            return .none
        }
    }

    /// The PNG of an image element (also the picture of a barcode): 1.2 named the field "image", 1.3 "_image"; a Bitmap
    /// keeps its PNG in "Data".
    private static func picture(of record: NRBFInstance, _ graph: NRBFGraph) -> Data? {
        let bitmap = graph.instance(record.member("_image")) ?? graph.instance(record.member("image"))
        return bitmap.flatMap { graph.bytes($0.member("Data")) }
    }

    /// Upstream `ZxingModel`: auto properties, stored as their backing fields (`member` finds those by the name).
    private static func barcodeModel(_ record: NRBFInstance, _ graph: NRBFGraph) -> LegacyElement.LegacyBarcodeModel {
        var model = LegacyElement.LegacyBarcodeModel()
        model.formatIndex = int(record, "FormatIndex", graph)
        model.qrCategoryIndex = int(record, "QrCategoryIndex", graph)
        model.wifiEncryptionIndex = int(record, "WifiEncryptionIndex", graph)
        for name in LegacyElement.LegacyBarcodeModel.textNames {
            if let text = graph.string(record.member(name)) { model.texts[name] = text }
        }
        if case .color(let color) = value(record.member("ForeColor"), graph) { model.foreColor = color }
        if case .color(let color) = value(record.member("BackColor"), graph) { model.backColor = color }
        model.roundedDots = bool(record.member("RoundedDots"))
        model.margin = intValue(record.member("Margin"))
        return model
    }

    private static func shadow(_ record: NRBFInstance, _ graph: NRBFGraph) -> LegacyElement.LegacyShadow {
        var darkness = 0.0
        if case .double(let value)? = record.member("_shadowDarkness") { darkness = value }
        return LegacyElement.LegacyShadow(darkness: darkness, size: int(record, "_shadowSize", graph),
                                          offsetX: int(record, "_shadowOffsetX", graph), offsetY: int(record, "_shadowOffsetY", graph))
    }

    private static func fields(of holder: NRBFInstance, in graph: NRBFGraph) -> [LegacyField] {
        listItems(graph.instance(holder.member("fields")), in: graph).compactMap { item in
            guard let field = graph.instance(item),
                  let name = graph.instance(field.member("FieldType")).flatMap({ graph.string($0.member("Name")) }),
                  !name.isEmpty else { return nil }
            return LegacyField(name: name, value: value(field.member("_myValue") ?? field.member("myValue"), graph))
        }
    }

    private static func value(_ raw: NRBFValue?, _ graph: NRBFGraph) -> LegacyValue {
        switch raw {
        case nil, .null?: return .null
        case .bool(let flag)?: return .bool(flag)
        case .int(let number)?: return .number(Double(number))
        case .uint(let number)?: return .number(Double(number))
        case .double(let number)?: return .number(number)
        case .string(let text)?: return .string(text)
        case .ticks?: return .unsupported("DateTime")
        case .object?:
            if let text = graph.string(raw) { return .string(text) }
            guard let record = graph.instance(raw) else { return .unsupported("array") }
            if record.typeName == "System.Drawing.Color" {
                return .color(LegacyColor(value: int64(record.member("value")) ?? 0, knownColor: intValue(record.member("knownColor")) ?? 0,
                                          state: intValue(record.member("state")) ?? 0, name: graph.string(record.member("name"))))
            }
            // An enum is a record with only "value__".
            if let number = int64(record.member("value__")) {
                return .enumeration(type: record.simpleName, value: number)
            }
            return .unsupported(record.typeName)
        }
    }

    /// The items of a List<T> (or a class derived from it, like DrawableContainerList): the first `_size` of `_items`.
    private static func listItems(_ list: NRBFInstance?, in graph: NRBFGraph) -> [NRBFValue] {
        guard let list, let items = graph.array(list.member("_items")) else { return [] }
        let size = min(max(intValue(list.member("_size")) ?? items.count, 0), items.count)
        return items.prefix(size).filter { $0 != .null }
    }

    /// The bytes of a MemoryStream: `_buffer` from `_origin` to `_length`.
    private static func memoryStream(_ stream: NRBFInstance?, _ graph: NRBFGraph) -> Data? {
        guard let stream, let buffer = graph.bytes(stream.member("_buffer")) else { return nil }
        let origin = min(max(intValue(stream.member("_origin")) ?? 0, 0), buffer.count)
        let length = min(max(intValue(stream.member("_length")) ?? buffer.count, origin), buffer.count)
        return buffer.subdata(in: origin..<length)
    }

    private static func point(_ record: NRBFInstance, _ graph: NRBFGraph) -> CGPoint {
        CGPoint(x: int(record, "x", graph), y: int(record, "y", graph))
    }

    private static func int(_ record: NRBFInstance, _ name: String, _ graph: NRBFGraph, _ fallback: Int = 0) -> Int {
        intValue(record.member(name)) ?? fallback
    }

    private static func int64(_ value: NRBFValue?) -> Int64? {
        switch value {
        case .int(let number)?: return number
        case .uint(let number)?: return Int64(clamping: number)
        default: return nil
        }
    }

    /// An integer, limited to what Int32 holds (positions and sizes of upstream are Int32).
    private static func intValue(_ value: NRBFValue?) -> Int? {
        int64(value).map { Int(min(max($0, Int64(Int32.min)), Int64(Int32.max))) }
    }

    private static func bool(_ value: NRBFValue?) -> Bool {
        if case .bool(let flag)? = value { return flag }
        return false
    }
}

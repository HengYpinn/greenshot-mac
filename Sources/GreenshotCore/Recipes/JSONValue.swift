// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A JSON value as a recipe file holds it (upstream reads recipe files with Newtonsoft `JToken`). Objects keep the
/// order of their members, so a recipe saved again keeps its layout, and look keys up case-insensitively like
/// upstream's parameter dictionaries (`StringComparer.OrdinalIgnoreCase`): files write `sourceType`, contracts say
/// `SourceType`. Also the value type of flow variables and expression results. Numbers are `Double` (JSON has one
/// number type); integral numbers are written without a fraction.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
}

/// One member of a JSON object, with the key spelled as in the file.
public struct JSONMember: Sendable, Hashable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

/// A JSON object: members in file order, keys looked up case-insensitively. Two objects are equal when they have the
/// same keys (exact spelling) with equal values, in any order (Newtonsoft `JToken.DeepEquals`).
public struct JSONObject: Sendable, Hashable, Sequence, ExpressibleByDictionaryLiteral {
    public private(set) var members: [JSONMember]

    public init(_ members: [JSONMember] = []) {
        self.members = members
    }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.members = elements.map { JSONMember($0.0, $0.1) }
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }
    public var keys: [String] { members.map(\.key) }
    public func makeIterator() -> IndexingIterator<[JSONMember]> { members.makeIterator() }

    /// The position of the member with this key (case-insensitive), nil when there is none.
    public func index(forKey key: String) -> Int? {
        members.firstIndex { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// Case-insensitive. Setting keeps the spelling and position of an existing key and appends a new one; nil removes.
    public subscript(key: String) -> JSONValue? {
        get { index(forKey: key).map { members[$0].value } }
        set {
            if let index = index(forKey: key) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(JSONMember(key, newValue))
            }
        }
    }

    public func contains(key: String) -> Bool { index(forKey: key) != nil }

    @discardableResult
    public mutating func removeValue(forKey key: String) -> JSONValue? {
        guard let index = index(forKey: key) else { return nil }
        return members.remove(at: index).value
    }

    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        guard lhs.members.count == rhs.members.count else { return false }
        return lhs.members.allSatisfy { member in rhs.members.contains { $0.key == member.key && $0.value == member.value } }
    }

    public func hash(into hasher: inout Hasher) {
        for member in members.sorted(by: { $0.key < $1.key }) {
            hasher.combine(member.key)
            hasher.combine(member.value)
        }
    }
}

/// Why a text is not JSON: the message and the character offset.
public struct JSONParseError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var offset: Int

    public init(message: String, offset: Int) {
        self.message = message
        self.offset = offset
    }

    public var errorDescription: String? { "\(message) (at character \(offset))" }
}

extension JSONValue {
    /// Parses UTF-8 (a byte order mark is skipped, like upstream's `StreamReader`), keeping the member order.
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONTextParser(bytes: [UInt8](data))
        return try parser.parseDocument()
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONTextParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }

    /// JSON text; indented like upstream's `Formatting.Indented` (two spaces, `"key": value`).
    public func serialized(indented: Bool = true) -> String {
        var out = ""
        JSONTextWriter.write(self, to: &out, indented: indented, level: 0)
        return out
    }

    public var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    public var doubleValue: Double? { if case .number(let value) = self { return value } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    public var objectValue: JSONObject? { if case .object(let value) = self { return value } else { return nil } }
    public var isNull: Bool { self == .null }

    /// The value converted like upstream's `GetParameter<T>` (`Convert.ChangeType`): "2" is 2, 2 is "2", "true" is
    /// true. Nil when it doesn't convert.
    public var asString: String? {
        switch self {
        case .string(let text): return text
        case .number(let number): return JSONValue.format(number)
        case .bool(let flag): return flag ? "True" : "False"
        case .null, .array, .object: return nil
        }
    }

    public var asInt: Int? {
        guard let number = asDouble, number.isFinite else { return nil }
        let rounded = number.rounded(.toNearestOrEven)
        guard rounded >= Double(Int.min), rounded <= Double(Int.max) else { return nil }
        return Int(rounded)
    }

    public var asDouble: Double? {
        switch self {
        case .number(let number): return number
        case .bool(let flag): return flag ? 1 : 0
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        case .null, .array, .object: return nil
        }
    }

    public var asBool: Bool? {
        switch self {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text):
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        case .null, .array, .object: return nil
        }
    }

    /// An array of strings, or a string split at `,` and `;` (upstream `GetParameter<List<string>>`, describer `GetStrings`).
    public var asStrings: [String]? {
        switch self {
        case .array(let items):
            return items.compactMap { $0.asString }
        case .string(let text):
            return text.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case .null, .bool, .number, .object:
            return nil
        }
    }

    /// The text of the value in an interpolated template, as upstream's `ToString()` gives it: "True", "42", "0.5", "".
    public var interpolationText: String {
        switch self {
        case .null: return ""
        case .array, .object: return serialized(indented: false)
        default: return asString ?? ""
        }
    }

    /// A number as .NET's `double.ToString()` writes it: integral values without a fraction, others shortest round-trip.
    static func format(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int64(number))
        }
        return "\(number)"
    }
}

/// Codable for embedding in other Codable types (settings, the trust store). Objects go through Foundation's keyed
/// containers, which don't keep the member order: recipe files use `JSONValue.parse` and `serialized()` instead.
extension JSONValue: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
                return
            }
            if let number = try? container.decode(Double.self) {
                self = .number(number)
                return
            }
            if let text = try? container.decode(String.self) {
                self = .string(text)
                return
            }
            if let items = try? container.decode([JSONValue].self) {
                self = .array(items)
                return
            }
        }
        let keyed = try decoder.container(keyedBy: Key.self)
        let keys = keyed.allKeys.sorted { $0.stringValue < $1.stringValue }
        var members: [JSONMember] = []
        for key in keys {
            members.append(JSONMember(key.stringValue, try keyed.decode(JSONValue.self, forKey: key)))
        }
        self = .object(JSONObject(members))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let flag):
            var container = encoder.singleValueContainer()
            try container.encode(flag)
        case .number(let number):
            var container = encoder.singleValueContainer()
            try container.encode(number)
        case .string(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .array(let items):
            var container = encoder.singleValueContainer()
            try container.encode(items)
        case .object(let object):
            var container = encoder.container(keyedBy: Key.self)
            for member in object {
                try container.encode(member.value, forKey: Key(stringValue: member.key))
            }
        }
    }
}

extension JSONObject {
    /// Typed reads of a member, converted like `JSONValue.asString` etc.
    public func string(_ key: String) -> String? { self[key]?.asString }
    public func int(_ key: String) -> Int? { self[key]?.asInt }
    public func double(_ key: String) -> Double? { self[key]?.asDouble }
    public func bool(_ key: String) -> Bool? { self[key]?.asBool }
    public func strings(_ key: String) -> [String]? { self[key]?.asStrings }
}

// MARK: - Parser and writer

/// A JSON parser that keeps the member order. Tolerant like Newtonsoft's reader in what recipe files written by hand
/// contain: a byte order mark, `//` and `/* */` comments, single-quoted strings, a comma before a closing bracket.
/// A member that repeats a key (case-insensitive) replaces its value, as the last one wins in upstream.
struct JSONTextParser {
    /// Deeper nesting is refused: recipe files can come from anyone (an AI tool, a download).
    static let maxDepth = 256

    let bytes: [UInt8]
    var index = 0
    var depth = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    mutating func parseDocument() throws -> JSONValue {
        try skipTrivia()
        let value = try parseValue()
        try skipTrivia()
        guard index == bytes.count else { throw error("Unexpected text after the JSON value") }
        return value
    }

    private func error(_ message: String) -> JSONParseError {
        JSONParseError(message: message, offset: index)
    }

    private mutating func skipTrivia() throws {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index += 1
            } else if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2F {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2A {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == 0x2A && bytes[index + 1] == 0x2F) { index += 1 }
                guard index + 1 < bytes.count else { throw error("Unterminated comment") }
                index += 2
            } else {
                return
            }
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard index < bytes.count else { throw error("Unexpected end of the text") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""), UInt8(ascii: "'"): return .string(try parseString())
        case UInt8(ascii: "t"): try expectWord("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectWord("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectWord("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
        default: throw error("Unexpected character '\(Character(UnicodeScalar(bytes[index])))'")
        }
    }

    private mutating func expectWord(_ word: String) throws {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw error("Unexpected literal")
        }
        index += expected.count
    }

    private mutating func enter() throws {
        depth += 1
        guard depth <= Self.maxDepth else { throw error("The JSON is nested too deeply") }
    }

    private mutating func parseObject() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        index += 1
        var members: [JSONMember] = []
        var positions: [String: Int] = [:]
        try skipTrivia()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(JSONObject(members))
        }
        while true {
            try skipTrivia()
            guard index < bytes.count else { throw error("Unterminated object") }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                break
            }
            guard bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") else {
                throw error("Expected a property name")
            }
            let key = try parseString()
            try skipTrivia()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("Expected ':' after a property name") }
            index += 1
            try skipTrivia()
            let value = try parseValue()
            let folded = key.lowercased()
            if let position = positions[folded] {
                members[position].value = value
            } else {
                positions[folded] = members.count
                members.append(JSONMember(key, value))
            }
            try skipTrivia()
            guard index < bytes.count else { throw error("Unterminated object") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                index += 1
                break
            } else {
                throw error("Expected ',' or '}' in an object")
            }
        }
        return .object(JSONObject(members))
    }

    private mutating func parseArray() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        index += 1
        var items: [JSONValue] = []
        while true {
            try skipTrivia()
            guard index < bytes.count else { throw error("Unterminated array") }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                break
            }
            items.append(try parseValue())
            try skipTrivia()
            guard index < bytes.count else { throw error("Unterminated array") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "]") {
                index += 1
                break
            } else {
                throw error("Expected ',' or ']' in an array")
            }
        }
        return .array(items)
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        func digits() { while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 } }
        digits()
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            digits()
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            digits()
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let number = Double(text) else {
            index = start
            throw error("Invalid number '\(text)'")
        }
        return number
    }

    private mutating func parseString() throws -> String {
        let quote = bytes[index]
        index += 1
        var buffer: [UInt8] = []
        while true {
            guard index < bytes.count else { throw error("Unterminated string") }
            let byte = bytes[index]
            if byte == quote {
                index += 1
                break
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else { throw error("Unterminated string") }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "\\"), UInt8(ascii: "/"): buffer.append(escaped)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if (0xD800...0xDBFF).contains(scalar), index + 1 < bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                        let save = index
                        index += 2
                        let low = try parseHex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            index = save
                        }
                    }
                    let character = UnicodeScalar(scalar).map(Character.init) ?? "\u{FFFD}"
                    buffer.append(contentsOf: Array(String(character).utf8))
                default:
                    throw error("Invalid escape in a string")
                }
            } else {
                buffer.append(byte)
                index += 1
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("Invalid \\u escape") }
        let text = String(decoding: bytes[index..<index + 4], as: UTF8.self)
        guard let value = UInt32(text, radix: 16) else { throw error("Invalid \\u escape") }
        index += 4
        return value
    }
}

/// Writes JSON like Newtonsoft's `Formatting.Indented` (two spaces, `"key": value`, `[]` and `{}` when empty, non-ASCII
/// text unescaped) or compact.
enum JSONTextWriter {
    static func write(_ value: JSONValue, to out: inout String, indented: Bool, level: Int) {
        switch value {
        case .null:
            out += "null"
        case .bool(let flag):
            out += flag ? "true" : "false"
        case .number(let number):
            out += number.isFinite ? JSONValue.format(number) : "null"
        case .string(let text):
            writeString(text, to: &out)
        case .array(let items):
            guard !items.isEmpty else {
                out += "[]"
                return
            }
            out += "["
            for (offset, item) in items.enumerated() {
                if offset > 0 { out += "," }
                newline(&out, indented: indented, level: level + 1)
                write(item, to: &out, indented: indented, level: level + 1)
            }
            newline(&out, indented: indented, level: level)
            out += "]"
        case .object(let object):
            guard !object.isEmpty else {
                out += "{}"
                return
            }
            out += "{"
            for (offset, member) in object.members.enumerated() {
                if offset > 0 { out += "," }
                newline(&out, indented: indented, level: level + 1)
                writeString(member.key, to: &out)
                out += indented ? ": " : ":"
                write(member.value, to: &out, indented: indented, level: level + 1)
            }
            newline(&out, indented: indented, level: level)
            out += "}"
        }
    }

    private static func newline(_ out: inout String, indented: Bool, level: Int) {
        guard indented else { return }
        out += "\n"
        out += String(repeating: "  ", count: level)
    }

    static func writeString(_ text: String, to out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

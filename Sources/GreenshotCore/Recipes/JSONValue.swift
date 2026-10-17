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
    public static func parse(_ data: Data) throws -> JSONValue { rcoreStub() }
    public static func parse(_ text: String) throws -> JSONValue { rcoreStub() }
    /// JSON text; indented like upstream's `Formatting.Indented` (two spaces, `"key": value`).
    public func serialized(indented: Bool = true) -> String { rcoreStub() }

    public var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    public var doubleValue: Double? { if case .number(let value) = self { return value } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    public var objectValue: JSONObject? { if case .object(let value) = self { return value } else { return nil } }
    public var isNull: Bool { self == .null }

    /// The value converted like upstream's `GetParameter<T>` (`Convert.ChangeType`): "2" is 2, 2 is "2", "true" is
    /// true. Nil when it doesn't convert.
    public var asString: String? { rcoreStub() }
    public var asInt: Int? { rcoreStub() }
    public var asDouble: Double? { rcoreStub() }
    public var asBool: Bool? { rcoreStub() }
    /// An array of strings, or a string split at `,` and `;` (upstream `GetParameter<List<string>>`, describer `GetStrings`).
    public var asStrings: [String]? { rcoreStub() }

    /// The text of the value in an interpolated template, as upstream's `ToString()` gives it: "True", "42", "0.5", "".
    public var interpolationText: String { rcoreStub() }
}

/// Codable for embedding in other Codable types (settings, the trust store). Objects go through Foundation's keyed
/// containers, which don't keep the member order: recipe files use `JSONValue.parse` and `serialized()` instead.
extension JSONValue: Codable {
    public init(from decoder: Decoder) throws { rcoreStub() }
    public func encode(to encoder: Encoder) throws { rcoreStub() }
}

extension JSONObject {
    /// Typed reads of a member, converted like `JSONValue.asString` etc.
    public func string(_ key: String) -> String? { self[key]?.asString }
    public func int(_ key: String) -> Int? { self[key]?.asInt }
    public func double(_ key: String) -> Double? { self[key]?.asDouble }
    public func bool(_ key: String) -> Bool? { self[key]?.asBool }
    public func strings(_ key: String) -> [String]? { self[key]?.asStrings }
}

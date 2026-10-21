// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreFoundation
import Foundation

/// The JSON text of the automation frames, as `JSONValue` (the recipe engine's JSON type). Foundation's
/// `JSONSerialization` reads and writes the text: the frames don't need the member order recipe files keep.
public enum IPCJSON {
    /// The object in `data`; nil when it isn't JSON or not an object.
    public static func parseObject(_ data: Data) -> JSONObject? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return value(from: any).objectValue
    }

    /// A value read by `JSONSerialization`.
    public static func value(from any: Any) -> JSONValue {
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let text = any as? String { return .string(text) }
        if let array = any as? [Any] { return .array(array.map(value(from:))) }
        if let dictionary = any as? [String: Any] {
            let members = dictionary.keys.sorted().map { key in JSONMember(key, value(from: dictionary[key] ?? NSNull())) }
            return .object(JSONObject(members))
        }
        return .null
    }

    /// The value for `JSONSerialization`; whole numbers become integers, so an exit code is written as `2`, not `2.0`.
    /// A number JSON can't hold (infinite or NaN, e.g. a recipe's `${x * 1}` with x = 1e999) becomes null, as the recipe
    /// engine's `JSONTextWriter` writes it: `JSONSerialization` would raise an Objective-C exception that ends the app.
    public static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let flag):
            return flag
        case .number(let number):
            guard number.isFinite else { return NSNull() }
            if number.rounded() == number, abs(number) < 9.0e15 { return Int64(number) }
            return number
        case .string(let text):
            return text
        case .array(let items):
            return items.map(foundationValue)
        case .object(let object):
            var dictionary: [String: Any] = [:]
            for member in object { dictionary[member.key] = foundationValue(member.value) }
            return dictionary
        }
    }

    /// Compact UTF-8 JSON of the object, keys sorted (stable output for tests and logs).
    public static func data(_ object: JSONObject) -> Data {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        return (try? JSONSerialization.data(withJSONObject: foundationValue(.object(object)), options: options)) ?? Data("{}".utf8)
    }

    public static func text(_ object: JSONObject) -> String {
        String(decoding: data(object), as: UTF8.self)
    }
}

extension JSONObject {
    /// A member as text, only when it is a string (no conversion, unlike the recipe engine's `string(_:)`).
    func ipcString(_ key: String) -> String? { self[key]?.stringValue }

    /// A member as an integer, when it is a whole number.
    func ipcInt(_ key: String) -> Int? {
        guard let number = self[key]?.doubleValue, number.rounded() == number, abs(number) < 9.0e15 else { return nil }
        return Int(number)
    }
}

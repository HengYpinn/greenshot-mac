// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The order-preserving JSON of the recipe files (upstream reads them with Newtonsoft `JToken`).
@Suite struct RecipeJSONTests {
    @Test func keepsMemberOrder() throws {
        let value = try JSONValue.parse(#"{"zeta": 1, "alpha": 2, "mid": 3}"#)
        let object = try #require(value.objectValue)
        #expect(object.keys == ["zeta", "alpha", "mid"])
    }

    @Test func looksKeysUpCaseInsensitively() throws {
        let value = try JSONValue.parse(#"{"sourceType": "Region"}"#)
        let object = try #require(value.objectValue)
        let found = object["SourceType"]
        #expect(found == .string("Region"))
        #expect(object.contains(key: "SOURCETYPE"))
    }

    @Test func settingAKeepsSpellingAndPosition() {
        var object: JSONObject = ["first": .number(1), "Second": .number(2)]
        object["second"] = .number(3)
        object["third"] = .bool(true)
        #expect(object.keys == ["first", "Second", "third"])
        #expect(object["SECOND"] == .number(3))
        object["first"] = nil
        #expect(object.keys == ["Second", "third"])
    }

    @Test func equalityIgnoresMemberOrder() {
        let one: JSONObject = ["a": .number(1), "b": .string("x")]
        let two: JSONObject = ["b": .string("x"), "a": .number(1)]
        #expect(one == two)
        #expect(one.hashValue == two.hashValue)
    }

    @Test func repeatedKeyReplacesTheValue() throws {
        let value = try JSONValue.parse(#"{"id": "one", "Id": "two"}"#)
        let object = try #require(value.objectValue)
        #expect(object.count == 1)
        #expect(object["id"] == .string("two"))
    }

    @Test func toleratesWhatHandWrittenFilesContain() throws {
        let text = "\u{FEFF}{\n  // a comment\n  'name': 'single',\n  /* block */ \"list\": [1, 2,],\n}"
        let value = try JSONValue.parse(text)
        let object = try #require(value.objectValue)
        #expect(object["name"] == .string("single"))
        #expect(object["list"] == .array([.number(1), .number(2)]))
    }

    @Test func byteOrderMarkInData() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"a": true}"#.utf8)
        let value = try JSONValue.parse(data)
        #expect(value == .object(["a": .bool(true)]))
    }

    @Test func escapesAndSurrogatePairs() throws {
        let value = try JSONValue.parse(#"["line\nbreak", "tab\t", "quote\"", "\u00e9", "\ud83d\ude00"]"#)
        let items = try #require(value.arrayValue)
        #expect(items[0] == .string("line\nbreak"))
        #expect(items[2] == .string("quote\""))
        #expect(items[3] == .string("é"))
        #expect(items[4] == .string("😀"))
    }

    @Test func errorsSayWhere() {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"{"a": }"#) }
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"{"a": 1} extra"#) }
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"["unterminated"#) }
        do {
            _ = try JSONValue.parse("[1, x]")
            Issue.record("expected an error")
        } catch let error as JSONParseError {
            #expect(error.offset == 4)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func refusesDeepNesting() {
        let text = String(repeating: "[", count: 300) + String(repeating: "]", count: 300)
        #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
    }

    @Test func writesLikeNewtonsoftIndented() {
        let value = JSONValue.object(["id": .string("a"), "list": .array([.number(1), .number(2.5)]), "empty": .array([]),
                                      "obj": .object([:]), "flag": .bool(false), "none": .null])
        let expected = """
        {
          "id": "a",
          "list": [
            1,
            2.5
          ],
          "empty": [],
          "obj": {},
          "flag": false,
          "none": null
        }
        """
        #expect(value.serialized() == expected)
        #expect(value.serialized(indented: false) == #"{"id":"a","list":[1,2.5],"empty":[],"obj":{},"flag":false,"none":null}"#)
    }

    @Test func writesEscapes() {
        let value = JSONValue.string("a\"b\\c\nd\u{01}é")
        #expect(value.serialized() == #""a\"b\\c\nd\u0001é""#)
    }

    @Test func roundTripsText() throws {
        let text = #"{"b":[true,null,"x",{"c":-1.25e3}],"a":"ü"}"#
        let value = try JSONValue.parse(text)
        #expect(value.serialized(indented: false) == #"{"b":[true,null,"x",{"c":-1250}],"a":"ü"}"#)
        let again = try JSONValue.parse(value.serialized())
        #expect(again == value)
    }

    @Test func conversionsLikeConvertChangeType() {
        #expect(JSONValue.string("2").asInt == 2)
        #expect(JSONValue.number(2).asString == "2")
        #expect(JSONValue.number(0.5).asString == "0.5")
        #expect(JSONValue.bool(true).asString == "True")
        #expect(JSONValue.string("TRUE").asBool == true)
        #expect(JSONValue.number(0).asBool == false)
        #expect(JSONValue.string("x").asInt == nil)
        #expect(JSONValue.number(2.5).asInt == 2)
        #expect(JSONValue.number(3.5).asInt == 4)
        #expect(JSONValue.null.asString == nil)
        #expect(JSONValue.string("Editor; Clipboard,File").asStrings == ["Editor", "Clipboard", "File"])
        #expect(JSONValue.array([.string("a"), .number(1)]).asStrings == ["a", "1"])
    }

    @Test func interpolationText() {
        #expect(JSONValue.null.interpolationText == "")
        #expect(JSONValue.bool(false).interpolationText == "False")
        #expect(JSONValue.number(2_073_600).interpolationText == "2073600")
        #expect(JSONValue.array([.number(1)]).interpolationText == "[1]")
    }

    @Test func codableBridge() throws {
        let value = JSONValue.object(["b": .array([.bool(true), .number(1), .string("s"), .null]), "a": .number(2)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A value in a .NET Remoting binary stream ([MS-NRBF]), the format of .NET's BinaryFormatter, in which Greenshot for
/// Windows 1.2 - 1.4 stores the elements of `.greenshot` and `.gst` files (upstream `Surface.SaveElementsToStream`).
enum NRBFValue: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    /// Strings, chars and decimals (decimals come as text).
    case string(String)
    /// Ticks of a DateTime or TimeSpan.
    case ticks(Int64)
    /// An object of the stream's object table (class instance, array or string): see `NRBFGraph.object(_:)`.
    case object(Int32)
}

/// An object of the stream: a class instance, an array or a string.
enum NRBFObject {
    case instance(NRBFInstance)
    case array([NRBFValue])
    case bytes(Data)
    case string(String)
}

/// An instance of a class: its type name (e.g. "Greenshot.Editor.Drawing.RectangleContainer") and its members, which
/// BinaryFormatter names "Class+field" for the fields of base classes.
struct NRBFInstance {
    var typeName: String
    var memberNames: [String]
    var values: [NRBFValue]

    /// The type name without namespace and generic arguments: "RectangleContainer", "FilterContainer+PreparedFilter".
    var simpleName: String {
        let withoutGenerics = typeName.split(separator: "[", maxSplits: 1).first.map(String.init) ?? typeName
        return withoutGenerics.split(separator: ".").last.map(String.init) ?? withoutGenerics
    }

    /// The member `name`: exact, as the backing field of an auto property, or a base class's "Class+name" (the
    /// lookup of upstream's BinaryFormatter-free reader, which covers the renames between Greenshot 1.2 and 1.4).
    func member(_ name: String) -> NRBFValue? {
        let backingField = "<\(name)>k__BackingField"
        var candidate: Int?
        for (index, member) in memberNames.enumerated() {
            if member == name || member == backingField { return values[index] }
            if candidate == nil, member.hasSuffix("+" + name) || member.hasSuffix("+" + backingField) { candidate = index }
        }
        return candidate.map { values[$0] }
    }
}

/// The decoded stream: the root and the table of objects that values point into.
struct NRBFGraph {
    var root: NRBFValue
    var objects: [Int32: NRBFObject]

    func object(_ value: NRBFValue?) -> NRBFObject? {
        guard case .object(let id)? = value else { return nil }
        return objects[id]
    }

    func instance(_ value: NRBFValue?) -> NRBFInstance? {
        guard case .instance(let instance)? = object(value) else { return nil }
        return instance
    }

    func string(_ value: NRBFValue?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .object?:
            if case .string(let text)? = object(value) { return text }
            return nil
        default: return nil
        }
    }

    func array(_ value: NRBFValue?) -> [NRBFValue]? {
        guard case .array(let items)? = object(value) else { return nil }
        return items
    }

    func bytes(_ value: NRBFValue?) -> Data? {
        guard case .bytes(let data)? = object(value) else { return nil }
        return data
    }
}

enum NRBFError: Error, Equatable {
    case truncated
    case notNRBF
    case unsupportedRecord(UInt8)
    case unsupportedType(UInt8)
    case badLength
    case unknownMetadata(Int32)
    case tooDeep
    case tooManyRecords
}

/// Decodes a .NET binary stream into values, without creating anything by its type name (upstream warns about
/// ysoserial payloads in `BinaryFormatterHelper`; here a crafted file can only produce values that are ignored).
/// Port of the record layer that upstream's BinaryFormatter-free reader takes from System.Formats.Nrbf
/// (Greenshot.Document.Legacy/LegacyElementReader.cs on upstream branch commit 7165e4ad).
struct NRBFDecoder {
    /// Limits for files from anywhere.
    static let maxRecords = 1_000_000
    static let maxDepth = 64
    /// The longest array or member list read (Greenshot's lists have a few dozen entries).
    static let maxCount = 1 << 22
    /// The most values (array items, members, member names) one stream may make, in all. Null records stand for many
    /// items and a class layout is used again by 9-byte records, so the bytes of the stream are no limit; Greenshot's
    /// files have a few thousand at most (a freehand line of 10,000 points: about 30,000).
    static let maxValues = 2_000_000

    private let bytes: [UInt8]
    private var position = 0
    private var objects: [Int32: NRBFObject] = [:]
    /// Class layouts by the id of the object that brought them, for `ClassWithId` records.
    private var layouts: [Int32: ClassLayout] = [:]
    private var records = 0
    private var depth = 0
    /// The values made so far, see `maxValues`.
    private var madeValues = 0

    private struct ClassLayout {
        var name: String
        var memberNames: [String]
        /// Nil for the record types without member types: every value is then a record.
        var memberTypes: [MemberType]?
    }

    private enum MemberType {
        case primitive(UInt8)
        case record
        case primitiveArray(UInt8)
    }

    /// A record read where a value goes: a value, or several nulls of an array.
    private enum Item {
        case value(NRBFValue)
        case nulls(Int)
        case end
    }

    private init(_ data: Data) {
        bytes = [UInt8](data)
    }

    /// The stream in `data` (up to its MessageEnd record).
    static func decode(_ data: Data) throws -> NRBFGraph {
        var decoder = NRBFDecoder(data)
        return try decoder.decodeStream()
    }

    private mutating func decodeStream() throws -> NRBFGraph {
        guard try byte() == 0 else { throw NRBFError.notNRBF }
        let rootID = try int32()
        _ = try int32() // header id
        let major = try int32()
        let minor = try int32()
        guard major == 1, minor == 0 else { throw NRBFError.notNRBF }
        while true {
            switch try item() {
            case .end:
                return NRBFGraph(root: rootID == 0 ? .null : .object(rootID), objects: objects)
            case .value, .nulls:
                continue
            }
        }
    }

    // MARK: Records

    /// Reads one record (and the BinaryLibrary records in front of it).
    private mutating func item() throws -> Item {
        // A loop, not a recursion, for the BinaryLibrary records: a stream of thousands of them in a row must not use up
        // the stack. Each counts as a record.
        while true {
            records += 1
            guard records <= Self.maxRecords else { throw NRBFError.tooManyRecords }
            let type = try byte()
            if type == 12 { // BinaryLibrary: its id and name, then the record it comes with
                _ = try int32()
                _ = try string()
                continue
            }
            return try record(type)
        }
    }

    /// The record of `type` (not a BinaryLibrary), its type byte read.
    private mutating func record(_ type: UInt8) throws -> Item {
        switch type {
        case 1: // ClassWithId
            let id = try int32()
            let metadataID = try int32()
            guard let layout = layouts[metadataID] else { throw NRBFError.unknownMetadata(metadataID) }
            return .value(try instance(id: id, layout: layout))
        case 2: // SystemClassWithMembers
            let (id, layout) = try classInfo(withTypes: false, library: false)
            return .value(try instance(id: id, layout: layout))
        case 3: // ClassWithMembers
            let (id, layout) = try classInfo(withTypes: false, library: true)
            return .value(try instance(id: id, layout: layout))
        case 4: // SystemClassWithMembersAndTypes
            let (id, layout) = try classInfo(withTypes: true, library: false)
            return .value(try instance(id: id, layout: layout))
        case 5: // ClassWithMembersAndTypes
            let (id, layout) = try classInfo(withTypes: true, library: true)
            return .value(try instance(id: id, layout: layout))
        case 6: // BinaryObjectString
            let id = try int32()
            objects[id] = .string(try string())
            return .value(.object(id))
        case 7:
            return .value(try binaryArray())
        case 8: // MemberPrimitiveTyped
            return .value(try primitive(try byte()))
        case 9: // MemberReference
            return .value(.object(try int32()))
        case 10: // ObjectNull
            return .nulls(1)
        case 11: // MessageEnd
            return .end
        case 13: // ObjectNullMultiple256
            return .nulls(Int(try byte()))
        case 14: // ObjectNullMultiple
            return .nulls(try count())
        case 15: // ArraySinglePrimitive
            let id = try int32()
            let length = try count()
            let elementType = try primitiveType()
            objects[id] = try primitiveArray(elementType, length: length)
            return .value(.object(id))
        case 16, 17: // ArraySingleObject, ArraySingleString
            let id = try int32()
            let length = try count()
            objects[id] = .array(try recordValues(length))
            return .value(.object(id))
        default:
            throw NRBFError.unsupportedRecord(type)
        }
    }

    /// ClassInfo (object id, name, member names), then MemberTypeInfo and the library id when the record has them.
    private mutating func classInfo(withTypes: Bool, library: Bool) throws -> (Int32, ClassLayout) {
        let id = try int32()
        let name = try string()
        let memberCount = try count()
        try make(memberCount)
        var names: [String] = []
        for _ in 0..<memberCount { names.append(try string()) }
        var types: [MemberType]?
        if withTypes {
            var binaryTypes: [UInt8] = []
            for _ in 0..<memberCount { binaryTypes.append(try byte()) }
            types = try binaryTypes.map { try memberType($0) }
        }
        if library { _ = try int32() }
        let layout = ClassLayout(name: name, memberNames: names, memberTypes: types)
        layouts[id] = layout
        return (id, layout)
    }

    /// A BinaryTypeEnumeration with its AdditionalInfo.
    private mutating func memberType(_ binaryType: UInt8) throws -> MemberType {
        switch binaryType {
        case 0: return .primitive(try primitiveType())
        case 1, 2, 5, 6: return .record
        case 3: // SystemClass: its name
            _ = try string()
            return .record
        case 4: // Class: name and library
            _ = try string()
            _ = try int32()
            return .record
        case 7: return .primitiveArray(try primitiveType())
        default: throw NRBFError.unsupportedType(binaryType)
        }
    }

    private mutating func instance(id: Int32, layout: ClassLayout) throws -> NRBFValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maxDepth else { throw NRBFError.tooDeep }
        // A layout is used again by 9-byte ClassWithId records: every instance counts its members.
        try make(layout.memberNames.count)
        var values: [NRBFValue] = []
        values.reserveCapacity(layout.memberNames.count)
        for index in layout.memberNames.indices {
            if case .primitive(let type)? = layout.memberTypes?[index] {
                values.append(try primitive(type))
            } else {
                values.append(try recordValue())
            }
        }
        objects[id] = .instance(NRBFInstance(typeName: layout.name, memberNames: layout.memberNames, values: values))
        return .object(id)
    }

    /// A member that is a record: an object, a reference, a string, a boxed primitive or null.
    private mutating func recordValue() throws -> NRBFValue {
        switch try item() {
        case .value(let value): return value
        case .nulls(let count) where count == 1: return .null
        default: throw NRBFError.badLength
        }
    }

    /// `length` array items that are records; null records may stand for several items.
    private mutating func recordValues(_ length: Int) throws -> [NRBFValue] {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maxDepth else { throw NRBFError.tooDeep }
        // Counted before they are read: one ObjectNullMultiple record of 5 bytes fills the whole array.
        try make(length)
        var values: [NRBFValue] = []
        values.reserveCapacity(min(length, 4096))
        while values.count < length {
            switch try item() {
            case .value(let value): values.append(value)
            case .nulls(let count):
                guard count <= length - values.count else { throw NRBFError.badLength }
                values.append(contentsOf: repeatElement(.null, count: count))
            case .end: throw NRBFError.truncated
            }
        }
        return values
    }

    /// BinaryArray: only single dimension arrays (with or without a lower bound), which is what Greenshot writes.
    private mutating func binaryArray() throws -> NRBFValue {
        let id = try int32()
        let arrayType = try byte()
        let rank = try int32()
        guard rank == 1, arrayType == 0 || arrayType == 3 else { throw NRBFError.unsupportedRecord(7) }
        let length = try count()
        if arrayType == 3 { _ = try int32() }
        let type = try memberType(try byte())
        switch type {
        case .primitive(let primitiveType):
            objects[id] = try primitiveArray(primitiveType, length: length)
        case .record, .primitiveArray:
            objects[id] = .array(try recordValues(length))
        }
        return .object(id)
    }

    private mutating func primitiveArray(_ type: UInt8, length: Int) throws -> NRBFObject {
        if type == 2 { // Byte: pictures, as many bytes as the stream has
            return .bytes(Data(try take(length)))
        }
        // Every primitive type read takes at least one byte (Null, 17, which takes none, is refused by
        // `primitiveType()` and `primitive(_:)`), so a longer array than the bytes left is cut off.
        guard length <= bytes.count - position else { throw NRBFError.truncated }
        try make(length)
        var values: [NRBFValue] = []
        values.reserveCapacity(min(length, 4096))
        for _ in 0..<length { values.append(try primitive(type)) }
        return .array(values)
    }

    // MARK: Primitives

    private mutating func primitive(_ type: UInt8) throws -> NRBFValue {
        switch type {
        case 1: return .bool(try byte() != 0)
        case 2: return .uint(UInt64(try byte()))
        case 3: return .string(try char())
        case 5: return .string(try string())
        case 6: return .double(Double(bitPattern: try uint64()))
        case 7: return .int(Int64(Int16(bitPattern: UInt16(truncatingIfNeeded: try littleEndian(2)))))
        case 8: return .int(Int64(try int32()))
        case 9: return .int(Int64(bitPattern: try uint64()))
        case 10: return .int(Int64(Int8(bitPattern: try byte())))
        case 11: return .double(Double(Float(bitPattern: UInt32(truncatingIfNeeded: try littleEndian(4)))))
        case 12, 13: return .ticks(Int64(bitPattern: try uint64()))
        case 14: return .uint(try littleEndian(2))
        case 15: return .uint(try littleEndian(4))
        case 16: return .uint(try uint64())
        // 17 (Null) is refused: it takes no bytes, so arrays and layouts of it would make values from nothing.
        // BinaryFormatter writes null members as ObjectNull records.
        case 18: return .string(try string())
        default: throw NRBFError.unsupportedType(type)
        }
    }

    /// A PrimitiveTypeEnumeration of a member or an array: any but Null (17), see `primitive(_:)`.
    private mutating func primitiveType() throws -> UInt8 {
        let type = try byte()
        guard type != 17 else { throw NRBFError.unsupportedType(type) }
        return type
    }

    /// Counts `count` more values against `maxValues`.
    private mutating func make(_ count: Int) throws {
        madeValues += count
        guard madeValues <= Self.maxValues else { throw NRBFError.tooManyRecords }
    }

    private mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw NRBFError.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count - position else { throw NRBFError.truncated }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    private mutating func littleEndian(_ size: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for (offset, byte) in try take(size).enumerated() {
            value |= UInt64(byte) << UInt64(8 * offset)
        }
        return value
    }

    private mutating func uint64() throws -> UInt64 {
        try littleEndian(8)
    }

    private mutating func int32() throws -> Int32 {
        Int32(bitPattern: UInt32(truncatingIfNeeded: try littleEndian(4)))
    }

    /// A length or count: not negative and at most `maxCount` (null records can stand for many items, so the bytes
    /// left are no limit; primitive arrays check those as they are read).
    private mutating func count() throws -> Int {
        let value = Int(try int32())
        guard value >= 0, value <= Self.maxCount else { throw NRBFError.badLength }
        return value
    }

    /// A LengthPrefixedString: the UTF-8 byte count in 7-bit groups, then the bytes.
    private mutating func string() throws -> String {
        var length = 0
        var shift = 0
        while true {
            let part = try byte()
            length |= Int(part & 0x7F) << shift
            if part & 0x80 == 0 { break }
            shift += 7
            guard shift <= 28 else { throw NRBFError.badLength }
        }
        return String(decoding: try take(length), as: UTF8.self)
    }

    /// A Char: one UTF-8 encoded character.
    private mutating func char() throws -> String {
        let first = try byte()
        let extra = first < 0x80 ? 0 : first >= 0xF0 ? 3 : first >= 0xE0 ? 2 : 1
        var utf8 = [first]
        utf8.append(contentsOf: try take(extra))
        return String(decoding: utf8, as: UTF8.self)
    }
}

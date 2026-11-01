// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Crafted BinaryFormatter streams (the elements of `.greenshot` and `.gst` files of Greenshot for Windows come from
/// anywhere): they must fail cleanly, without using up the stack or the memory.
struct NRBFLimitsTests {
    @Test func thousandsOfLibraryRecordsInARowDoNotUseUpTheStack() throws {
        var payload = NRBFTestStream.header()
        let library: [UInt8] = [12] + NRBFTestStream.int32(2) + [0] // BinaryLibrary 2, empty name
        for _ in 0..<50_000 { payload.append(contentsOf: library) }
        payload.append(11) // MessageEnd
        let graph = try NRBFDecoder.decode(payload)
        #expect(graph.root == .object(1))
        #expect(graph.objects.isEmpty)
    }

    @Test func membersAreFoundByNameBackingFieldOrBaseClass() {
        let names = ["Base+a", "a", "<b>k__BackingField", "Other+<c>k__BackingField", "Base+c", "A+B+d", "e+"]
        let instance = NRBFInstance(typeName: "T", memberNames: names, values: names.indices.map { .int(Int64($0)) })
        // An exact name (or backing field) comes before a base class's field of that name; else the first base class's.
        #expect(instance.member("a") == .int(1))
        #expect(instance.member("b") == .int(2))
        #expect(instance.member("c") == .int(3))
        #expect(instance.member("d") == .int(5))
        #expect(instance.member("B+d") == .int(5))
        #expect(instance.member("") == .int(6))
        #expect(instance.member("x") == nil)
    }

    @Test func lookingUpMembersOfAHugeClassStaysFast() {
        // A class with 100,000 members (a crafted file can have a million): each lookup went over all of them.
        let names = (0..<100_000).map { "Base+m\($0)" }
        let instance = NRBFInstance(typeName: "T", memberNames: names, values: Array(repeating: .null, count: names.count))
        let clock = ContinuousClock()
        let start = clock.now
        var found = 0
        for index in 0..<200 where instance.member("missing\(index)") != nil { found += 1 }
        #expect(found == 0)
        #expect(instance.member("m99999") == .null)
        #expect(clock.now - start < .seconds(2))
    }

    @Test func libraryRecordsCountAsRecords() {
        var payload = NRBFTestStream.header()
        let library: [UInt8] = [12] + NRBFTestStream.int32(2) + [0]
        for _ in 0...NRBFDecoder.maxRecords { payload.append(contentsOf: library) }
        payload.append(11)
        #expect(throws: NRBFError.tooManyRecords) { try NRBFDecoder.decode(payload) }
    }

    /// ArraySingleObject `id` of `length` items, all of them one ObjectNullMultiple record: 14 bytes.
    private static func nullArray(id: Int32, length: Int32) -> [UInt8] {
        [16] + NRBFTestStream.int32(id) + NRBFTestStream.int32(length) + [14] + NRBFTestStream.int32(length)
    }

    @Test func aFewBytesOfNullsCannotFillTheMemory() {
        var payload = NRBFTestStream.header()
        payload.append(contentsOf: Self.nullArray(id: 1, length: 1 << 22))
        payload.append(11)
        #expect(throws: NRBFError.tooManyRecords) { try NRBFDecoder.decode(payload) }
    }

    @Test func theLimitIsForTheWholeStream() {
        // 20 arrays of a million nulls each (280 bytes) made 2 GB before.
        var payload = NRBFTestStream.header()
        for id in 1...20 { payload.append(contentsOf: Self.nullArray(id: Int32(id), length: 1 << 20)) }
        payload.append(11)
        #expect(throws: NRBFError.tooManyRecords) { try NRBFDecoder.decode(payload) }
    }

    @Test func arraysUpToTheLimitStillDecode() throws {
        var payload = NRBFTestStream.header()
        payload.append(contentsOf: Self.nullArray(id: 1, length: 1000))
        payload.append(11)
        let graph = try NRBFDecoder.decode(payload)
        let items = try #require(graph.array(.object(1)))
        #expect(items.count == 1000)
    }

    @Test func nullAsAPrimitiveTypeIsRefused() {
        // A class whose 3 members are primitives of type 17 (Null), which take no bytes: a layout of millions of them,
        // used again by 9-byte ClassWithId records, made millions of values from nothing.
        var layout = NRBFTestStream.header()
        layout.append(contentsOf: NRBFTestStream.bytes([4], NRBFTestStream.int32(1), NRBFTestStream.string("Nulls"),
                                                       NRBFTestStream.int32(3)))
        for name in ["a", "b", "c"] { layout.append(contentsOf: NRBFTestStream.string(name)) }
        layout.append(contentsOf: [0, 0, 0, 17, 17, 17])
        layout.append(11)
        #expect(throws: NRBFError.unsupportedType(17)) { try NRBFDecoder.decode(layout) }
        // An array of them: ArraySinglePrimitive of type 17.
        var array = NRBFTestStream.header()
        array.append(contentsOf: NRBFTestStream.bytes([15], NRBFTestStream.int32(1), NRBFTestStream.int32(1 << 22),
                                                      [17]))
        array.append(11)
        #expect(throws: NRBFError.unsupportedType(17)) { try NRBFDecoder.decode(array) }
    }
}

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

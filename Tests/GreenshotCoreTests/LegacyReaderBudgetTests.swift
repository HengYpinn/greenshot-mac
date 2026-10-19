// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Crafted `.greenshot` payloads whose elements all point at one big object: the decoder's limits count the records of
/// the stream, so the reader has its own budget for what it builds.
struct LegacyReaderBudgetTests {
    private static func i32(_ value: Int32) -> [UInt8] { NRBFTestStream.int32(value) }

    /// A root List<object> (id 1, `_size` = `count`) whose array (id 3) holds `count` references made by `reference(i)`,
    /// then `shared`, the records of the objects they reach.
    private static func payload(count: Int, reference: (Int) -> Int32, tail: [UInt8]) -> Data {
        var data = NRBFTestStream.header()
        data.append(contentsOf: NRBFTestStream.bytes([12], i32(2), NRBFTestStream.string("Lib, Version=1.0.0.0")))
        data.append(contentsOf: NRBFTestStream.bytes([5], i32(1), NRBFTestStream.string("System.Collections.Generic.List`1"),
                                                     i32(2), NRBFTestStream.string("_items"), NRBFTestStream.string("_size"),
                                                     [5, 0, 8], i32(2)))
        data.append(contentsOf: [9] + i32(3))
        data.append(contentsOf: i32(Int32(count)))
        data.append(contentsOf: NRBFTestStream.bytes([16], i32(3), i32(Int32(count))))
        for index in 0..<count { data.append(contentsOf: [9] + i32(reference(index))) }
        data.append(contentsOf: tail)
        data.append(11)
        return data
    }

    /// Object 4: a container with one member `member` (an Object) referencing object 5; objects 1000+ reuse its layout.
    private static func containers(_ typeName: String, member: String, count: Int) -> [UInt8] {
        var bytes = NRBFTestStream.bytes([5], i32(4), NRBFTestStream.string(typeName), i32(1), NRBFTestStream.string(member), [2], i32(2))
        bytes.append(contentsOf: [9] + i32(5))
        for index in 1..<max(count, 1) {
            bytes.append(contentsOf: NRBFTestStream.bytes([1], i32(Int32(1000 + index)), i32(4), [9], i32(5)))
        }
        return bytes
    }

    private static func freehandTail(elements: Int, points: Int) -> [UInt8] {
        var tail = containers("FreehandContainer", member: "capturePoints", count: elements)
        // Object 5: a List with `_items` (array 6) and `_size`; array 6: `points` references to one Point (object 7).
        tail.append(contentsOf: NRBFTestStream.bytes([5], i32(5), NRBFTestStream.string("System.Collections.Generic.List`1"), i32(2),
                                                     NRBFTestStream.string("_items"), NRBFTestStream.string("_size"), [2, 0, 8], i32(2)))
        tail.append(contentsOf: [9] + i32(6))
        tail.append(contentsOf: i32(Int32(points)))
        tail.append(contentsOf: NRBFTestStream.bytes([16], i32(6), i32(Int32(points))))
        for _ in 0..<points { tail.append(contentsOf: [9] + i32(7)) }
        tail.append(contentsOf: NRBFTestStream.bytes([5], i32(7), NRBFTestStream.string("System.Drawing.Point"), i32(2),
                                                     NRBFTestStream.string("x"), NRBFTestStream.string("y"), [0, 0, 8, 8], i32(2),
                                                     i32(1), i32(2)))
        return tail
    }

    private static func svgTail(elements: Int, size: Int) -> [UInt8] {
        var tail = containers("SvgContainer", member: "_svgContent", count: elements)
        // Object 5: a MemoryStream with `_buffer` (6), `_origin`, `_length`; object 6: one `size` bytes array.
        tail.append(contentsOf: NRBFTestStream.bytes([5], i32(5), NRBFTestStream.string("System.IO.MemoryStream"), i32(3),
                                                     NRBFTestStream.string("_buffer"), NRBFTestStream.string("_origin"),
                                                     NRBFTestStream.string("_length"), [2, 0, 0, 8, 8], i32(2)))
        tail.append(contentsOf: [9] + i32(6))
        tail.append(contentsOf: i32(0))
        tail.append(contentsOf: i32(Int32(size)))
        tail.append(contentsOf: NRBFTestStream.bytes([15], i32(6), i32(Int32(size)), [2]))
        tail.append(contentsOf: [UInt8](repeating: 0x3C, count: size))
        return tail
    }

    @Test func tenThousandElementsSharingOneFreehandLineAreRefused() {
        let data = Self.payload(count: 10_000, reference: { Int32($0 == 0 ? 4 : 1000 + $0) }, tail: Self.freehandTail(elements: 10_000, points: 900_000))
        let clock = ContinuousClock()
        let start = clock.now
        #expect(throws: NRBFError.tooManyRecords) { try GreenshotLegacyReader.elements(fromPayload: data) }
        #expect(clock.now - start < .seconds(15))
    }

    @Test func tenThousandElementsSharingOneSvgBufferAreRefused() {
        let size = 4 << 20
        let data = Self.payload(count: 10_000, reference: { Int32($0 == 0 ? 4 : 1000 + $0) }, tail: Self.svgTail(elements: 10_000, size: size))
        let clock = ContinuousClock()
        let start = clock.now
        #expect(throws: NRBFError.tooManyRecords) { try GreenshotLegacyReader.elements(fromPayload: data) }
        #expect(clock.now - start < .seconds(15))
    }

    @Test func aFewElementsSharingAPictureAreStillRead() throws {
        let data = Self.payload(count: 3, reference: { Int32($0 == 0 ? 4 : 1000 + $0) }, tail: Self.svgTail(elements: 3, size: 1000))
        let elements = try GreenshotLegacyReader.elements(fromPayload: data)
        #expect(elements.count == 3)
    }

    @Test func oneObjectListedManyTimesIsOneElement() throws {
        let data = Self.payload(count: 10_000, reference: { _ in 4 }, tail: Self.freehandTail(elements: 1, points: 1000))
        let elements = try GreenshotLegacyReader.elements(fromPayload: data)
        #expect(elements.count == 1)
        guard case .freehand(let points) = elements[0].content else {
            Issue.record("not a freehand element")
            return
        }
        #expect(points.count == 1000)
    }
}

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
}

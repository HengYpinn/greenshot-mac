// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A lossless WebP encoder (the VP8L bitstream of RFC 9649), because macOS reads WebP but has no encoder for it.
/// Upstream writes WebP with ImageSharp's `WebpEncoder` (`ImageSharpFileFormatHandler`), lossy with the JPEG quality;
/// here it is lossless, which suits screenshots and ignores the quality.
///
/// Kept simple: the subtract-green transform, LZ77 backward references found with a hash chain, distances written as
/// plain distances (no 2D distance codes), no color cache and one prefix code group for the whole image.
enum ImageWebPEncoder {
    /// VP8L stores the width and height in 14 bits each.
    /// The VP8L header could hold 16384, but decoders (libwebp's `WEBP_MAX_DIMENSION`, so ImageIO) stop at 16383.
    static let maxSide = 16383

    static func encode(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= maxSide, height <= maxSide else {
            throw ImageExportError.tooLarge(.webp, maxSide: maxSide)
        }
        guard var argb = straightARGB(image) else { throw ImageExportError.encodingFailed(.webp) }
        let usesAlpha = argb.contains { $0 >> 24 != 0xFF }
        subtractGreen(&argb)
        let tokens = backwardReferences(argb)

        var writer = BitWriter()
        writer.write(0x2F, 8)
        writer.write(UInt32(width - 1), 14)
        writer.write(UInt32(height - 1), 14)
        writer.write(usesAlpha ? 1 : 0, 1)
        writer.write(0, 3)
        // One transform: subtract green (type 2), then the end of the transforms.
        writer.write(1, 1)
        writer.write(2, 2)
        writer.write(0, 1)
        // No color cache, no meta prefix codes.
        writer.write(0, 1)
        writer.write(0, 1)

        var green = [Int](repeating: 0, count: 256 + 24)
        var red = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var alpha = [Int](repeating: 0, count: 256)
        var distance = [Int](repeating: 0, count: 40)
        for token in tokens {
            if let copy = Token.copy(token) {
                green[256 + prefix(copy.length).code] += 1
                distance[prefix(copy.distance + 120).code] += 1
            } else {
                let pixel = UInt32(truncatingIfNeeded: token)
                green[Int(pixel >> 8 & 0xFF)] += 1
                red[Int(pixel >> 16 & 0xFF)] += 1
                blue[Int(pixel & 0xFF)] += 1
                alpha[Int(pixel >> 24)] += 1
            }
        }
        let greenCode = PrefixCode(histogram: green, writer: &writer)
        let redCode = PrefixCode(histogram: red, writer: &writer)
        let blueCode = PrefixCode(histogram: blue, writer: &writer)
        let alphaCode = PrefixCode(histogram: alpha, writer: &writer)
        let distanceCode = PrefixCode(histogram: distance, writer: &writer)

        for token in tokens {
            if let copy = Token.copy(token) {
                let length = prefix(copy.length)
                greenCode.write(256 + length.code, to: &writer)
                writer.write(UInt32(length.extra), length.extraBits)
                let far = prefix(copy.distance + 120)
                distanceCode.write(far.code, to: &writer)
                writer.write(UInt32(far.extra), far.extraBits)
            } else {
                let pixel = UInt32(truncatingIfNeeded: token)
                greenCode.write(Int(pixel >> 8 & 0xFF), to: &writer)
                redCode.write(Int(pixel >> 16 & 0xFF), to: &writer)
                blueCode.write(Int(pixel & 0xFF), to: &writer)
                alphaCode.write(Int(pixel >> 24), to: &writer)
            }
        }
        return riff(writer.finish())
    }

    /// The RIFF container with the one VP8L chunk (padded to an even size).
    static func riff(_ payload: [UInt8]) -> Data {
        let padded = payload.count + payload.count % 2
        var data = Data("RIFF".utf8)
        data.append(contentsOf: le32(4 + 8 + padded))
        data.append(contentsOf: Array("WEBPVP8L".utf8))
        data.append(contentsOf: le32(payload.count))
        data.append(contentsOf: payload)
        if payload.count % 2 == 1 { data.append(0) }
        return data
    }

    // MARK: Pixels

    /// The pixels top row first as ARGB with straight (not premultiplied) alpha; fully transparent pixels are 0.
    static func straightARGB(_ image: CGImage) -> [UInt32]? {
        guard let bgra = ImageFormatEncoders.straightBGRA(image) else { return nil }
        return bgra.map { pixel in
            // B G R A → A R G B
            let blue = pixel >> 24
            let green = pixel >> 16 & 0xFF
            let red = pixel >> 8 & 0xFF
            let alpha = pixel & 0xFF
            return alpha << 24 | red << 16 | green << 8 | blue
        }
    }

    /// The subtract-green transform: red and blue minus green, modulo 256 (the decoder adds it back).
    static func subtractGreen(_ argb: inout [UInt32]) {
        for i in argb.indices {
            let pixel = argb[i]
            let green = pixel >> 8 & 0xFF
            let red = ((pixel >> 16 & 0xFF) &+ 256 &- green) & 0xFF
            let blue = ((pixel & 0xFF) &+ 256 &- green) & 0xFF
            argb[i] = pixel & 0xFF00_FF00 | red << 16 | blue
        }
    }

    // MARK: LZ77

    /// A literal pixel (its ARGB in the low 32 bits) or, with the top bit set, a copy of `length` pixels (bits 32...44)
    /// from `distance` pixels back (the low 32 bits). Eight bytes, as a big capture has millions of them.
    enum Token {
        static func literal(_ pixel: UInt32) -> UInt64 { UInt64(pixel) }

        static func copy(length: Int, distance: Int) -> UInt64 {
            1 << 63 | UInt64(length) << 32 | UInt64(distance)
        }

        static func copy(_ token: UInt64) -> (length: Int, distance: Int)? {
            guard token >> 63 == 1 else { return nil }
            return (Int(token >> 32 & 0x1FFF), Int(token & 0xFFFF_FFFF))
        }
    }

    static let maxLength = 4096
    /// The largest distance code is 1 048 576; distance codes 1...120 are the 2D codes, which this encoder doesn't use.
    static let maxDistance = (1 << 20) - 120

    /// Greedy LZ77 with a hash chain over pairs of pixels: the longest match of at least 3 pixels among the last 32
    /// places with the same pair, else a literal.
    static func backwardReferences(_ argb: [UInt32]) -> [UInt64] {
        let count = argb.count
        let hashBits = 18
        var head = [Int32](repeating: -1, count: 1 << hashBits)
        var previous = [Int32](repeating: -1, count: count)
        var tokens: [UInt64] = []
        tokens.reserveCapacity(count / 4)
        argb.withUnsafeBufferPointer { pixels in
            func hash(_ i: Int) -> Int {
                let a = pixels[i] &* 0x9E37_79B1
                let b = pixels[i + 1] &* 0x85EB_CA6B
                return Int((a ^ (b >> 7) ^ b) >> UInt32(32 - hashBits))
            }
            func insert(_ i: Int) {
                guard i + 1 < count else { return }
                let h = hash(i)
                previous[i] = head[h]
                head[h] = Int32(i)
            }
            var i = 0
            while i < count {
                var bestLength = 0
                var bestDistance = 0
                if i + 1 < count {
                    let limit = min(maxLength, count - i)
                    var candidate = Int(head[hash(i)])
                    var tries = 0
                    while candidate >= 0, tries < 32, i - candidate <= maxDistance {
                        if bestLength < limit, pixels[candidate + bestLength] == pixels[i + bestLength] {
                            var length = 0
                            while length < limit, pixels[candidate + length] == pixels[i + length] { length += 1 }
                            if length > bestLength {
                                bestLength = length
                                bestDistance = i - candidate
                                if length == limit { break }
                            }
                        }
                        candidate = Int(previous[candidate])
                        tries += 1
                    }
                }
                if bestLength >= 3 {
                    tokens.append(Token.copy(length: bestLength, distance: bestDistance))
                    for j in i..<(i + bestLength) { insert(j) }
                    i += bestLength
                } else {
                    tokens.append(Token.literal(pixels[i]))
                    insert(i)
                    i += 1
                }
            }
        }
        return tokens
    }

    /// The prefix code of a length or distance code (RFC 9649 "LZ77 Prefix Coding"): 1...4 are codes 0...3, bigger
    /// values a code for their two highest bits plus the rest as extra bits.
    static func prefix(_ value: Int) -> (code: Int, extraBits: Int, extra: Int) {
        if value <= 4 { return (value - 1, 0, 0) }
        let d = value - 1
        let highest = Int.bitWidth - 1 - d.leadingZeroBitCount
        let second = (d >> (highest - 1)) & 1
        let extraBits = highest - 1
        return (2 * highest + second, extraBits, d & ((1 << extraBits) - 1))
    }

    static func le32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
    }
}

// MARK: - Prefix codes

/// A canonical prefix (Huffman) code of one alphabet, written into the stream when it is made: a "simple" code for one
/// or two symbols below 256, else a "normal" code whose code lengths are themselves run-length and prefix coded.
struct PrefixCode {
    private(set) var lengths: [Int]
    private(set) var codes: [UInt32]
    /// One symbol only: the decoder reads it with zero bits.
    private(set) var isSingle: Bool

    /// The order the code length code's lengths are written in.
    static let codeLengthOrder = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    init(histogram: [Int], writer: inout BitWriter) {
        let used = histogram.indices.filter { histogram[$0] > 0 }
        lengths = [Int](repeating: 0, count: histogram.count)
        if used.count <= 2 && used.allSatisfy({ $0 < 256 }) {
            // Simple code. An unused alphabet still needs a code: symbol 0.
            let symbols = used.isEmpty ? [0] : used
            writer.write(1, 1)
            writer.write(UInt32(symbols.count - 1), 1)
            if symbols[0] < 2 {
                writer.write(0, 1)
                writer.write(UInt32(symbols[0]), 1)
            } else {
                writer.write(1, 1)
                writer.write(UInt32(symbols[0]), 8)
            }
            if symbols.count == 2 { writer.write(UInt32(symbols[1]), 8) }
            for symbol in symbols { lengths[symbol] = 1 }
            isSingle = symbols.count == 1
        } else {
            lengths = Self.codeLengths(histogram, limit: 15)
            isSingle = used.count == 1
            Self.writeNormal(lengths, writer: &writer)
        }
        codes = Self.canonicalCodes(lengths)
    }

    func write(_ symbol: Int, to writer: inout BitWriter) {
        guard !isSingle else { return }
        writer.write(codes[symbol], lengths[symbol])
    }

    /// A normal code: the code lengths as run-length symbols (16 repeats the last length 3...6 times, 17 and 18 are
    /// 3...10 and 11...138 zeros), coded with a code length code of at most 7 bits.
    static func writeNormal(_ lengths: [Int], writer: inout BitWriter) {
        var tokens: [(symbol: Int, extraBits: Int, extra: Int)] = []
        var i = 0
        while i < lengths.count {
            let value = lengths[i]
            var run = 1
            while i + run < lengths.count, lengths[i + run] == value { run += 1 }
            i += run
            if value == 0 {
                while run >= 11 {
                    let n = min(run, 138)
                    tokens.append((18, 7, n - 11))
                    run -= n
                }
                if run >= 3 {
                    tokens.append((17, 3, run - 3))
                    run = 0
                }
                for _ in 0..<run { tokens.append((0, 0, 0)) }
            } else {
                tokens.append((value, 0, 0))
                run -= 1
                while run >= 3 {
                    let n = min(run, 6)
                    tokens.append((16, 2, n - 3))
                    run -= n
                }
                for _ in 0..<run { tokens.append((value, 0, 0)) }
            }
        }
        var histogram = [Int](repeating: 0, count: 19)
        for token in tokens { histogram[token.symbol] += 1 }
        let codeLengthLengths = codeLengths(histogram, limit: 7)
        let codeLengthCodes = canonicalCodes(codeLengthLengths)
        let single = codeLengthLengths.filter { $0 > 0 }.count == 1
        var count = 19
        while count > 4, codeLengthLengths[codeLengthOrder[count - 1]] == 0 { count -= 1 }
        writer.write(0, 1)
        writer.write(UInt32(count - 4), 4)
        for index in 0..<count { writer.write(UInt32(codeLengthLengths[codeLengthOrder[index]]), 3) }
        // The lengths of the whole alphabet follow (no max_symbol).
        writer.write(0, 1)
        for token in tokens {
            if !single { writer.write(codeLengthCodes[token.symbol], codeLengthLengths[token.symbol]) }
            if token.extraBits > 0 { writer.write(UInt32(token.extra), token.extraBits) }
        }
    }

    /// Huffman code lengths of at most `limit` bits: rebuilt with halved counts until they fit. One used symbol gets
    /// length 1 (it is then read with zero bits).
    static func codeLengths(_ histogram: [Int], limit: Int) -> [Int] {
        var lengths = [Int](repeating: 0, count: histogram.count)
        let used = histogram.indices.filter { histogram[$0] > 0 }
        guard used.count > 1 else {
            if let only = used.first { lengths[only] = 1 }
            return lengths
        }
        var counts = histogram
        while true {
            let depths = huffmanDepths(counts)
            if depths.max() ?? 0 <= limit { return depths }
            counts = counts.map { $0 > 0 ? max(1, $0 / 2) : 0 }
        }
    }

    /// The depth of every used symbol in a Huffman tree of `counts` (two queues: leaves by count, then merged nodes).
    static func huffmanDepths(_ counts: [Int]) -> [Int] {
        // Nodes: leaves first, then the merged ones; `parent` links them.
        var weights: [Int] = []
        var symbols: [Int] = []
        for (symbol, count) in counts.enumerated() where count > 0 {
            weights.append(count)
            symbols.append(symbol)
        }
        let leafOrder = weights.indices.sorted { weights[$0] != weights[$1] ? weights[$0] < weights[$1] : symbols[$0] < symbols[$1] }
        var parent = [Int](repeating: -1, count: weights.count)
        var merged: [Int] = []
        var leafIndex = 0
        var mergedIndex = 0
        func takeSmallest() -> Int {
            let leafAvailable = leafIndex < leafOrder.count
            let mergedAvailable = mergedIndex < merged.count
            if leafAvailable && (!mergedAvailable || weights[leafOrder[leafIndex]] <= weights[merged[mergedIndex]]) {
                leafIndex += 1
                return leafOrder[leafIndex - 1]
            }
            mergedIndex += 1
            return merged[mergedIndex - 1]
        }
        for _ in 0..<(leafOrder.count - 1) {
            let a = takeSmallest()
            let b = takeSmallest()
            let node = weights.count
            weights.append(weights[a] + weights[b])
            parent.append(-1)
            parent[a] = node
            parent[b] = node
            merged.append(node)
        }
        var depths = [Int](repeating: 0, count: counts.count)
        for (leaf, symbol) in symbols.enumerated() {
            var depth = 0
            var node = leaf
            while parent[node] >= 0 {
                node = parent[node]
                depth += 1
            }
            depths[symbol] = depth
        }
        return depths
    }

    /// DEFLATE-style canonical codes, bit-reversed because the stream is written from the lowest bit up.
    static func canonicalCodes(_ lengths: [Int]) -> [UInt32] {
        var countPerLength = [Int](repeating: 0, count: 16)
        for length in lengths where length > 0 { countPerLength[length] += 1 }
        var next = [Int](repeating: 0, count: 16)
        var code = 0
        for bits in 1..<16 {
            code = (code + countPerLength[bits - 1]) << 1
            next[bits] = code
        }
        return lengths.map { length in
            guard length > 0 else { return 0 }
            let value = next[length]
            next[length] += 1
            var reversed: UInt32 = 0
            for bit in 0..<length where value & (1 << bit) != 0 { reversed |= 1 << UInt32(length - 1 - bit) }
            return reversed
        }
    }
}

/// Bits written from the lowest bit of each byte up, as VP8L reads them.
struct BitWriter {
    private(set) var bytes: [UInt8] = []
    private var buffer: UInt64 = 0
    private var used = 0

    mutating func write(_ value: UInt32, _ bits: Int) {
        guard bits > 0 else { return }
        buffer |= (UInt64(value) & ((1 << UInt64(bits)) - 1)) << UInt64(used)
        used += bits
        while used >= 8 {
            bytes.append(UInt8(buffer & 0xFF))
            buffer >>= 8
            used -= 8
        }
    }

    mutating func finish() -> [UInt8] {
        if used > 0 {
            bytes.append(UInt8(buffer & 0xFF))
            buffer = 0
            used = 0
        }
        return bytes
    }
}

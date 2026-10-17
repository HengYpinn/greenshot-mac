// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Data Matrix ECC 200 (ISO/IEC 16022), which upstream gets from ZXing's `DataMatrixWriter`; Core Image can't make it.
/// The text is encoded in ASCII mode (two digits per codeword; ZXing also tries C40, Text, X12, EDIFACT and Base 256 for a
/// smaller symbol), padded, given Reed-Solomon error correction and placed like ISO 16022 Annex F, in the smallest square
/// symbol that holds it (10 × 10 to 144 × 144).
enum DataMatrixEncoder {
    /// A square symbol size (ISO 16022 table 7; ZXing `SymbolInfo`).
    struct Symbol: Equatable {
        /// Modules per side, finder and timing patterns included.
        let side: Int
        /// Data modules per side of one region.
        let regionSide: Int
        /// Regions per side.
        let regions: Int
        let dataCodewords: Int
        /// Error correction codewords of each Reed-Solomon block.
        let blockErrorCodewords: Int
        /// Interleaved Reed-Solomon blocks.
        let blocks: Int

        /// The data modules per side, without the finder and timing patterns.
        var mappingSide: Int { regionSide * regions }
        var errorCodewords: Int { blockErrorCodewords * blocks }
    }

    static let symbols: [Symbol] = [
        Symbol(side: 10, regionSide: 8, regions: 1, dataCodewords: 3, blockErrorCodewords: 5, blocks: 1),
        Symbol(side: 12, regionSide: 10, regions: 1, dataCodewords: 5, blockErrorCodewords: 7, blocks: 1),
        Symbol(side: 14, regionSide: 12, regions: 1, dataCodewords: 8, blockErrorCodewords: 10, blocks: 1),
        Symbol(side: 16, regionSide: 14, regions: 1, dataCodewords: 12, blockErrorCodewords: 12, blocks: 1),
        Symbol(side: 18, regionSide: 16, regions: 1, dataCodewords: 18, blockErrorCodewords: 14, blocks: 1),
        Symbol(side: 20, regionSide: 18, regions: 1, dataCodewords: 22, blockErrorCodewords: 18, blocks: 1),
        Symbol(side: 22, regionSide: 20, regions: 1, dataCodewords: 30, blockErrorCodewords: 20, blocks: 1),
        Symbol(side: 24, regionSide: 22, regions: 1, dataCodewords: 36, blockErrorCodewords: 24, blocks: 1),
        Symbol(side: 26, regionSide: 24, regions: 1, dataCodewords: 44, blockErrorCodewords: 28, blocks: 1),
        Symbol(side: 32, regionSide: 14, regions: 2, dataCodewords: 62, blockErrorCodewords: 36, blocks: 1),
        Symbol(side: 36, regionSide: 16, regions: 2, dataCodewords: 86, blockErrorCodewords: 42, blocks: 1),
        Symbol(side: 40, regionSide: 18, regions: 2, dataCodewords: 114, blockErrorCodewords: 48, blocks: 1),
        Symbol(side: 44, regionSide: 20, regions: 2, dataCodewords: 144, blockErrorCodewords: 56, blocks: 1),
        Symbol(side: 48, regionSide: 22, regions: 2, dataCodewords: 174, blockErrorCodewords: 68, blocks: 1),
        Symbol(side: 52, regionSide: 24, regions: 2, dataCodewords: 204, blockErrorCodewords: 42, blocks: 2),
        Symbol(side: 64, regionSide: 14, regions: 4, dataCodewords: 280, blockErrorCodewords: 56, blocks: 2),
        Symbol(side: 72, regionSide: 16, regions: 4, dataCodewords: 368, blockErrorCodewords: 36, blocks: 4),
        Symbol(side: 80, regionSide: 18, regions: 4, dataCodewords: 456, blockErrorCodewords: 48, blocks: 4),
        Symbol(side: 88, regionSide: 20, regions: 4, dataCodewords: 576, blockErrorCodewords: 56, blocks: 4),
        Symbol(side: 96, regionSide: 22, regions: 4, dataCodewords: 696, blockErrorCodewords: 68, blocks: 4),
        Symbol(side: 104, regionSide: 24, regions: 4, dataCodewords: 816, blockErrorCodewords: 56, blocks: 6),
        Symbol(side: 120, regionSide: 18, regions: 6, dataCodewords: 1050, blockErrorCodewords: 68, blocks: 6),
        Symbol(side: 132, regionSide: 20, regions: 6, dataCodewords: 1304, blockErrorCodewords: 62, blocks: 8),
        // Its 1558 data codewords make 8 blocks of 156 and 2 of 155.
        Symbol(side: 144, regionSide: 22, regions: 6, dataCodewords: 1558, blockErrorCodewords: 62, blocks: 10),
    ]

    static func matrix(_ payload: String) throws -> BarcodeMatrix {
        let data = codewords(payload)
        guard let symbol = symbols.first(where: { $0.dataCodewords >= data.count }) else { throw BarcodeError.tooLong }
        let all = errorCorrected(padded(data, to: symbol.dataCodewords), symbol: symbol)
        return assemble(placed(all, side: symbol.mappingSide), symbol: symbol)
    }

    /// The data modules per side of a region of the symbol with `symbolSide` modules per side.
    static func regionSide(symbolSide: Int) -> Int {
        symbols.first { $0.side == symbolSide }?.regionSide ?? symbolSide - 2
    }

    // MARK: Encodation

    /// ECI 26, UTF-8: for text that isn't ASCII, so that readers know how to read the bytes.
    static let utf8ECI: [UInt8] = [241, 27]

    /// ASCII mode (ZXing `ASCIIEncoder`): two digits in one codeword (130 + their value), ASCII as its value + 1, other
    /// bytes after an upper shift (235) as their value − 127.
    static func codewords(_ text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        var result: [UInt8] = bytes.contains { $0 > 127 } ? utf8ECI : []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if index + 1 < bytes.count, isDigit(byte), isDigit(bytes[index + 1]) {
                result.append(130 + (byte - 48) * 10 + (bytes[index + 1] - 48))
                index += 2
                continue
            }
            if byte > 127 {
                result += [235, byte - 127]
            } else {
                result.append(byte + 1)
            }
            index += 1
        }
        return result
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }

    /// The data filled up to the symbol's capacity: 129, then pad codewords scrambled by their position
    /// (`HighLevelEncoder.randomize253State`).
    static func padded(_ data: [UInt8], to capacity: Int) -> [UInt8] {
        var result = data
        if result.count < capacity { result.append(129) }
        while result.count < capacity {
            let position = result.count + 1
            let pseudoRandom = (149 * position) % 253 + 1
            let value = 129 + pseudoRandom
            result.append(UInt8(value <= 254 ? value : value - 254))
        }
        return result
    }

    // MARK: Error correction

    /// GF(256) with the polynomial x⁸ + x⁵ + x³ + x² + 1 (0x12D): exponents and logarithms of α = 2.
    private static let field: (exp: [Int], log: [Int]) = {
        var exp = [Int](repeating: 0, count: 512)
        var log = [Int](repeating: 0, count: 256)
        var x = 1
        for i in 0..<255 {
            exp[i] = x
            log[x] = i
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x12D }
        }
        for i in 255..<512 { exp[i] = exp[i - 255] }
        return (exp, log)
    }()

    private static func multiply(_ a: Int, _ b: Int) -> Int {
        guard a != 0, b != 0 else { return 0 }
        return field.exp[field.log[a] + field.log[b]]
    }

    /// The `count` Reed-Solomon codewords of `data`, with the generator polynomial of roots α¹ … α^count.
    static func reedSolomon(_ data: [UInt8], count: Int) -> [UInt8] {
        var generator = [1]
        for i in 1...count {
            var next = [Int](repeating: 0, count: generator.count + 1)
            for (j, coefficient) in generator.enumerated() {
                next[j] ^= coefficient
                next[j + 1] ^= multiply(coefficient, field.exp[i])
            }
            generator = next
        }
        var remainder = [Int](repeating: 0, count: count)
        for byte in data {
            let factor = Int(byte) ^ remainder[0]
            remainder.removeFirst()
            remainder.append(0)
            for k in 0..<count { remainder[k] ^= multiply(factor, generator[k + 1]) }
        }
        return remainder.map { UInt8($0) }
    }

    /// The data followed by the error correction codewords; with several blocks, data codeword i belongs to block
    /// i mod blocks and their error correction codewords are interleaved the same way (`ErrorCorrection.encodeECC200`).
    /// The 144 × 144 symbol is the exception: its two shorter blocks (the last two) come first in each round of error
    /// correction codewords, as ISO 16022 has it and readers expect (ZXing's `DataBlock.getDataBlocks`, `specialVersion`).
    static func errorCorrected(_ data: [UInt8], symbol: Symbol) -> [UInt8] {
        var result = data + [UInt8](repeating: 0, count: symbol.errorCodewords)
        let shorterBlocks = symbol.side == 144 ? 2 : 0
        for block in 0..<symbol.blocks {
            let blockData = stride(from: block, to: data.count, by: symbol.blocks).map { data[$0] }
            let correction = reedSolomon(blockData, count: symbol.blockErrorCodewords)
            let slot = (block + shorterBlocks) % symbol.blocks
            for (index, codeword) in correction.enumerated() {
                result[data.count + index * symbol.blocks + slot] = codeword
            }
        }
        return result
    }

    // MARK: Placement

    /// The codewords placed in the data area (`side` × `side`, row by row) like ISO 16022 Annex F (ZXing
    /// `DefaultPlacement`): diagonal sweeps of L-shaped ("utah") characters, with the four corner cases.
    static func placed(_ codewords: [UInt8], side: Int) -> [Bool] {
        var placement = Placement(codewords: codewords, rows: side, columns: side)
        placement.place()
        return placement.bits.map { $0 == 1 }
    }

    private struct Placement {
        let codewords: [UInt8]
        let rows: Int
        let columns: Int
        /// -1 while a module is still free.
        var bits: [Int8]

        init(codewords: [UInt8], rows: Int, columns: Int) {
            self.codewords = codewords
            self.rows = rows
            self.columns = columns
            bits = [Int8](repeating: -1, count: rows * columns)
        }

        func isSet(_ row: Int, _ column: Int) -> Bool { bits[row * columns + column] >= 0 }

        mutating func set(_ row: Int, _ column: Int, _ dark: Bool) { bits[row * columns + column] = dark ? 1 : 0 }

        /// Bit `bit` (1 is the highest) of codeword `index` at `row`, `column`, wrapped around the edges.
        mutating func module(_ row: Int, _ column: Int, _ index: Int, _ bit: Int) {
            var row = row
            var column = column
            if row < 0 {
                row += rows
                column += 4 - ((rows + 4) % 8)
            }
            if column < 0 {
                column += columns
                row += 4 - ((columns + 4) % 8)
            }
            let value = index < codewords.count ? Int(codewords[index]) : 0
            set(row, column, value & (1 << (8 - bit)) != 0)
        }

        mutating func utah(_ row: Int, _ column: Int, _ index: Int) {
            module(row - 2, column - 2, index, 1)
            module(row - 2, column - 1, index, 2)
            module(row - 1, column - 2, index, 3)
            module(row - 1, column - 1, index, 4)
            module(row - 1, column, index, 5)
            module(row, column - 2, index, 6)
            module(row, column - 1, index, 7)
            module(row, column, index, 8)
        }

        mutating func corner(_ positions: [(Int, Int)], _ index: Int) {
            for (bit, position) in positions.enumerated() {
                module(position.0, position.1, index, bit + 1)
            }
        }

        mutating func place() {
            var index = 0
            var row = 4
            var column = 0
            repeat {
                if row == rows && column == 0 {
                    corner([(rows - 1, 0), (rows - 1, 1), (rows - 1, 2), (0, columns - 2), (0, columns - 1),
                            (1, columns - 1), (2, columns - 1), (3, columns - 1)], index)
                    index += 1
                }
                if row == rows - 2 && column == 0 && columns % 4 != 0 {
                    corner([(rows - 3, 0), (rows - 2, 0), (rows - 1, 0), (0, columns - 4), (0, columns - 3),
                            (0, columns - 2), (0, columns - 1), (1, columns - 1)], index)
                    index += 1
                }
                if row == rows - 2 && column == 0 && columns % 8 == 4 {
                    corner([(rows - 3, 0), (rows - 2, 0), (rows - 1, 0), (0, columns - 2), (0, columns - 1),
                            (1, columns - 1), (2, columns - 1), (3, columns - 1)], index)
                    index += 1
                }
                if row == rows + 4 && column == 2 && columns % 8 == 0 {
                    corner([(rows - 1, 0), (rows - 1, columns - 1), (0, columns - 3), (0, columns - 2),
                            (0, columns - 1), (1, columns - 3), (1, columns - 2), (1, columns - 1)], index)
                    index += 1
                }
                // Up and to the right…
                repeat {
                    if row < rows && column >= 0 && !isSet(row, column) {
                        utah(row, column, index)
                        index += 1
                    }
                    row -= 2
                    column += 2
                } while row >= 0 && column < columns
                row += 1
                column += 3
                // …then down and to the left.
                repeat {
                    if row >= 0 && column < columns && !isSet(row, column) {
                        utah(row, column, index)
                        index += 1
                    }
                    row += 2
                    column -= 2
                } while row < rows && column >= 0
                row += 3
                column += 1
            } while row < rows || column < columns
            // A bottom right corner left free gets its fixed pattern.
            if !isSet(rows - 1, columns - 1) {
                set(rows - 1, columns - 1, true)
                set(rows - 2, columns - 2, true)
            }
            for i in bits.indices where bits[i] < 0 { bits[i] = 0 }
        }
    }

    /// The symbol: every region framed by its finder pattern (solid left and bottom edges) and timing pattern
    /// (alternating top and right edges) (`DataMatrixWriter.encodeLowLevel`).
    static func assemble(_ data: [Bool], symbol: Symbol) -> BarcodeMatrix {
        let side = symbol.side
        let mapping = symbol.mappingSide
        let region = symbol.regionSide
        var modules = [Bool](repeating: false, count: side * side)
        var y = 0
        for dataRow in 0..<mapping {
            if dataRow % region == 0 {
                for x in 0..<side { modules[y * side + x] = x % 2 == 0 }
                y += 1
            }
            var x = 0
            for dataColumn in 0..<mapping {
                if dataColumn % region == 0 {
                    modules[y * side + x] = true
                    x += 1
                }
                modules[y * side + x] = data[dataRow * mapping + dataColumn]
                x += 1
                if dataColumn % region == region - 1 {
                    modules[y * side + x] = dataRow % 2 == 0
                    x += 1
                }
            }
            y += 1
            if dataRow % region == region - 1 {
                for x in 0..<side { modules[y * side + x] = true }
                y += 1
            }
        }
        return BarcodeMatrix(width: side, height: side, modules: modules)
    }
}

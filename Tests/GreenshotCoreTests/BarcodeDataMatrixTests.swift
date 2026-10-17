// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
import Vision
@testable import GreenshotCore

/// Data Matrix ECC 200: codewords, error correction, symbol sizes, and symbols Vision reads.
struct BarcodeDataMatrixTests {
    @Test func theStandardsExampleCodewords() {
        // ISO/IEC 16022 annex: "123456" is 142 164 186 in a 10 × 10 symbol, with 114 25 5 88 102.
        let data = DataMatrixEncoder.codewords("123456")
        #expect(data == [142, 164, 186])
        let symbol = DataMatrixEncoder.symbols[0]
        let all = DataMatrixEncoder.errorCorrected(DataMatrixEncoder.padded(data, to: symbol.dataCodewords), symbol: symbol)
        #expect(all == [142, 164, 186, 114, 25, 5, 88, 102])
    }

    @Test func asciiEncodation() {
        #expect(DataMatrixEncoder.codewords("A") == [66])
        #expect(DataMatrixEncoder.codewords("a1") == [98, 50])
        #expect(DataMatrixEncoder.codewords("123") == [142, 52])
        // Text that isn't ASCII: ECI 26 (UTF-8), then each byte above 127 after an upper shift.
        #expect(DataMatrixEncoder.codewords("é") == [241, 27, 235, 68, 235, 42])
    }

    @Test func padCodewordsAreScrambledByPosition() {
        // After the 129, each pad is 129 + ((149 × position) mod 253) + 1, less 254 when it is bigger than 254.
        #expect(DataMatrixEncoder.padded([66], to: 5) == [66, 129, 70, 220, 115])
    }

    @Test func theSmallestSymbolThatHoldsTheText() throws {
        #expect(try BarcodeGenerator.matrix(.dataMatrix, payload: "123456").width == 10)
        #expect(try BarcodeGenerator.matrix(.dataMatrix, payload: "1234567").width == 12)
        #expect(try BarcodeGenerator.matrix(.dataMatrix, payload: String(repeating: "A", count: 44)).width == 26)
        #expect(try BarcodeGenerator.matrix(.dataMatrix, payload: String(repeating: "A", count: 45)).width == 32)
        let digits = String(repeating: "7", count: 3116)
        #expect(try BarcodeGenerator.matrix(.dataMatrix, payload: digits).width == 144)
        #expect(throws: BarcodeError.tooLong) { try BarcodeGenerator.matrix(.dataMatrix, payload: digits + "77") }
    }

    @Test func everySymbolSizeAddsUp() {
        for symbol in DataMatrixEncoder.symbols {
            #expect(symbol.regions * (symbol.regionSide + 2) == symbol.side, "\(symbol.side)")
            // The data area holds all codewords, 8 modules each (4 are left over in some sizes).
            let modules = symbol.mappingSide * symbol.mappingSide
            let codewords = symbol.dataCodewords + symbol.errorCodewords
            #expect(modules / 8 == codewords, "\(symbol.side)")
        }
    }

    @Test func finderAndTimingPatterns() throws {
        let matrix = try BarcodeGenerator.matrix(.dataMatrix, payload: "123456")
        #expect((0..<10).allSatisfy { matrix[0, $0] })
        #expect((0..<10).allSatisfy { matrix[$0, 9] })
        #expect((0..<10).map { matrix[$0, 0] } == (0..<10).map { $0 % 2 == 0 })
        #expect((0..<10).map { matrix[9, $0] } == (0..<10).map { $0 % 2 == 1 || $0 == 9 })
    }

    /// One symbol of each kind of layout: one region, 4 regions, 2 interleaved blocks, 16 regions, and the 144 × 144
    /// symbol with its unequal blocks.
    static let layouts: [(String, Int)] = [
        ("123456", 10),
        ("Greenshot for Mac", 18),
        (String(repeating: "Greenshot ", count: 5), 32),
        (String(repeating: "Data Matrix 0123456789 ", count: 10), 52),
        (String(repeating: "Greenshot 64 ", count: 20), 64),
        (String(repeating: "0123456789", count: 300), 144),
    ]

    /// Read back by Vision from the element drawing.
    @Test(arguments: layouts)
    func visionReadsTheSymbol(_ text: String, _ side: Int) throws {
        let matrix = try BarcodeGenerator.matrix(.dataMatrix, payload: text)
        #expect(matrix.width == side)
        var spec = BarcodeSpec()
        spec.symbology = .dataMatrix
        spec.text = text
        let size = CGSize(width: CGFloat(side + 2) * 8, height: CGFloat(side + 2) * 8)
        let payloads = try BarcodeElementTests.decoded(spec, as: [.dataMatrix], size: size)
        #expect(payloads == [text], "\(side) × \(side)")
    }

    @Test func otherAlphabetsReadBackThroughTheECI() throws {
        var spec = BarcodeSpec()
        spec.symbology = .dataMatrix
        spec.text = "日本語テキスト"
        let payloads = try BarcodeElementTests.decoded(spec, as: [.dataMatrix], size: CGSize(width: 400, height: 400))
        #expect(payloads == ["日本語テキスト"])
    }

    @Test func the144SymbolPutsItsShorterBlocksFirst() {
        let symbol = DataMatrixEncoder.symbols[DataMatrixEncoder.symbols.count - 1]
        let data = (0..<symbol.dataCodewords).map { UInt8($0 % 251) }
        let all = DataMatrixEncoder.errorCorrected(data, symbol: symbol)
        // Block 8 (data codewords 8, 18, …) is the 9th block and one of the two shorter ones.
        let block8 = stride(from: 8, to: data.count, by: 10).map { data[$0] }
        let first = DataMatrixEncoder.reedSolomon(block8, count: 62).first
        #expect(block8.count == 155)
        #expect(all[symbol.dataCodewords] == first)
    }

    @Test func roundDotsKeepTheFinderEdgesAndStillRead() throws {
        var spec = BarcodeSpec()
        spec.symbology = .dataMatrix
        spec.text = String(repeating: "Greenshot ", count: 4)
        spec.roundedDots = true
        let payloads = try BarcodeElementTests.decoded(spec, as: [.dataMatrix], size: CGSize(width: 400, height: 400))
        #expect(payloads == [spec.text])
    }
}

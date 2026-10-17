// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The bar code encoders (ZXing.Net's one-dimensional writers): check digits, patterns, the texts they refuse.
struct BarcodeLinearTests {
    func row(_ symbology: BarcodeSymbology, _ text: String) throws -> String {
        try BarcodeGenerator.matrix(symbology, payload: text).row(0)
    }

    // MARK: EAN and UPC

    @Test func gtinCheckDigitsOfTheStandardExamples() {
        #expect(LinearBarcode.gtinCheckDigit([5, 9, 0, 1, 2, 3, 4, 1, 2, 3, 4, 5]) == 7)
        #expect(LinearBarcode.gtinCheckDigit([9, 6, 3, 8, 5, 0, 7]) == 4)
        #expect(LinearBarcode.gtinCheckDigit([0, 3, 6, 0, 0, 0, 2, 9, 1, 4, 5]) == 2)
        #expect(LinearBarcode.gtinCheckDigit([4, 0, 0, 6, 3, 8, 1, 3, 3, 3, 9, 3]) == 1)
    }

    @Test func ean13Layout() throws {
        let bars = try row(.ean13, "5901234123457")
        #expect(bars.count == 95)
        #expect(bars.hasPrefix("101"))
        #expect(bars.hasSuffix("101"))
        // The first digit 5 is not drawn: it picks L G G L L G for the next six (9 in L is 0001011).
        let second = bars.dropFirst(3).prefix(7)
        #expect(second == "0001011")
        // The middle guard after six digits.
        let middle = bars.dropFirst(45).prefix(5)
        #expect(middle == "01010")
        // The check digit is computed when it's missing.
        #expect(try row(.ean13, "590123412345") == bars)
    }

    @Test func eanAndUpcRefuseWrongTexts() {
        #expect(throws: BarcodeError.wrongCheckDigit(expected: 7)) { try BarcodeGenerator.matrix(.ean13, payload: "5901234123450") }
        #expect(throws: BarcodeError.wrongLength("EAN-13 takes 12 digits, or 13 with the check digit.")) {
            try BarcodeGenerator.matrix(.ean13, payload: "12345")
        }
        #expect(throws: BarcodeError.invalidCharacters("EAN-8 takes digits only.")) {
            try BarcodeGenerator.matrix(.ean8, payload: "12a4567")
        }
        #expect(throws: BarcodeError.wrongCheckDigit(expected: 2)) { try BarcodeGenerator.matrix(.upcA, payload: "036000291450") }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.upcE, payload: "2425261") }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.upcE, payload: "042526") }
    }

    @Test func ean8AndUpcLayouts() throws {
        let ean8 = try row(.ean8, "9638507")
        #expect(ean8.count == 67)
        #expect(try row(.ean8, "96385074") == ean8)
        // UPC-A is EAN-13 with a leading 0.
        #expect(try row(.upcA, "03600029145") == row(.ean13, "003600029145"))
        let upcE = try row(.upcE, "0425261")
        #expect(upcE.count == 51)
        #expect(upcE.hasSuffix("010101"))
        #expect(try row(.upcE, "04252614") == upcE)
    }

    @Test func upcEStandsForItsUpcA() {
        #expect(LinearBarcode.upcAExpansion([0, 4, 2, 5, 2, 6, 1]) == [0, 4, 2, 1, 0, 0, 0, 0, 5, 2, 6])
        #expect(LinearBarcode.upcAExpansion([0, 1, 2, 3, 4, 5, 3]) == [0, 1, 2, 3, 0, 0, 0, 0, 0, 4, 5])
        #expect(LinearBarcode.upcAExpansion([1, 1, 2, 3, 4, 5, 4]) == [1, 1, 2, 3, 4, 0, 0, 0, 0, 0, 5])
        #expect(LinearBarcode.upcAExpansion([0, 1, 2, 3, 4, 5, 7]) == [0, 1, 2, 3, 4, 5, 0, 0, 0, 0, 7])
    }

    // MARK: Code 39 and Code 93

    @Test func code39CharactersAreFramedByAsterisks() throws {
        let bars = try row(.code39, "A")
        // * = narrow bar, wide space, narrow bar, narrow space, wide bar, narrow space, wide bar, narrow space, narrow bar.
        let asterisk: String = "100101101101"
        #expect(bars.hasPrefix(asterisk))
        #expect(bars.hasSuffix(asterisk))
        // A = wide bar, n, n, wide space, n, n, n, n, wide bar.
        let expected: String = [asterisk, "110101001011", asterisk].joined(separator: "0")
        #expect(bars == expected)
    }

    @Test func code39FullASCII() throws {
        #expect(try LinearBarcode.code39FullASCII("a!@ \u{0}") == Array("+A/A%V %U"))
        #expect(try row(.code39, "Hi") == row(.code39, "H+I"))
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.code39, payload: "é") }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.code39, payload: String(repeating: "A", count: 81)) }
        // Converted to full ASCII, 41 lower case letters are 82 characters.
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.code39, payload: String(repeating: "a", count: 41)) }
    }

    @Test func code93CheckCharactersOfTheTextbookExample() throws {
        // TEST93 has the check characters + and 6.
        let indexes = try LinearBarcode.code93Indexes("TEST93")
        let checks = indexes.suffix(2).map { LinearBarcode.code93Alphabet[$0] }
        #expect(checks == ["+", "6"])
        let bars = try row(.code93, "TEST93")
        // Start, 6 characters, 2 checks, stop: 9 modules each, and the termination bar.
        #expect(bars.count == 91)
        #expect(bars.hasPrefix("101011110"))
        #expect(bars.hasSuffix("1010111101"))
    }

    @Test func code93FullASCII() throws {
        #expect(try LinearBarcode.code93Extended("a!:@ $") == Array("dAcAcZbV $"))
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.code93, payload: "ü") }
    }

    // MARK: Codabar, ITF, MSI, Plessey

    @Test func codabarGuards() throws {
        #expect(try LinearBarcode.codabarText("12345") == Array("A12345A"))
        #expect(try LinearBarcode.codabarText("1") == Array("A1A"))
        #expect(try LinearBarcode.codabarText("b40156d") == Array("B40156D"))
        #expect(try LinearBarcode.codabarText("T123N") == Array("T123N"))
        #expect(throws: (any Error).self) { try LinearBarcode.codabarText("A123") }
        #expect(throws: (any Error).self) { try LinearBarcode.codabarText("123D") }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.codabar, payload: "12X45") }
        // The alternate guards draw as A to D.
        #expect(try row(.codabar, "T123N") == row(.codabar, "A123B"))
    }

    @Test func itf() throws {
        let bars = try row(.itf, "12")
        // Start 1010; 1 (wide n n n wide) in the bars and 2 (n wide n n wide) in the spaces; stop wide bar, n, n.
        let expected: String = ["1010", "111010001010111000", "11101"].joined()
        #expect(bars == expected)
        #expect(throws: BarcodeError.wrongLength("ITF takes an even number of digits; this is 3.")) {
            try BarcodeGenerator.matrix(.itf, payload: "123")
        }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.itf, payload: "12a4") }
    }

    @Test func msiAddsItsMod10CheckDigit() throws {
        #expect(LinearBarcode.msiCheckDigit([1, 2, 3, 4, 5, 6, 7]) == 4)
        #expect(LinearBarcode.msiCheckDigit([8, 0, 5, 2, 3]) == 4)
        let bars = try row(.msi, "1")
        // Start 110, the digit 1 and its check digit 8 as four bits each (1 = 110, 0 = 100), stop 1001.
        let expected: String = ["110", "100100100110", "110100100100", "1001"].joined()
        #expect(bars == expected)
    }

    @Test func plesseyCRCMatchesPolynomialDivision() {
        // The check bits are the remainder of the data bits (with 8 zeros) divided by x⁸+x⁷+x⁶+x⁵+x³+1.
        for text in ["0", "1", "12345", "ABCDEF", "F0F0"] {
            let dataBits = Array(text).flatMap { character -> [Int] in
                let value = LinearBarcode.plesseyAlphabet.firstIndex(of: character) ?? 0
                return (0..<4).map { (value >> $0) & 1 }
            }
            #expect(LinearBarcode.plesseyCRC(dataBits) == remainder(dataBits), "\(text)")
        }
    }

    /// Long division over GF(2), written independently of the encoder.
    func remainder(_ bits: [Int]) -> [Int] {
        let polynomial = [1, 1, 1, 1, 0, 1, 0, 0, 1]
        var work = bits + Array(repeating: 0, count: 8)
        for start in 0..<bits.count where work[start] == 1 {
            for (offset, coefficient) in polynomial.enumerated() {
                work[start + offset] = (work[start + offset] + coefficient) % 2
            }
        }
        return Array(work.suffix(8))
    }

    @Test func plesseyLayout() throws {
        let bars = try row(.plessey, "1")
        // Start 1101, data bits 1000 (lowest first), 8 check bits, termination bar, end pattern: 5 modules per bit.
        let bits: Int = 4 + 4 + 8
        let modules: Int = bits * 5 + 25
        #expect(bars.count == modules)
        let start: String = ["11100", "11100", "10000", "11100", "11100", "10000"].joined()
        #expect(bars.hasPrefix(start))
        let end: String = ["11111", "00001", "00001", "00011", "00011"].joined()
        #expect(bars.hasSuffix(end))
        #expect(try row(.plessey, "ab") == row(.plessey, "AB"))
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.plessey, payload: "G") }
    }
}

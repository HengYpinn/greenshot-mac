// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The bar codes upstream gets from ZXing.Net's one-dimensional writers (`ZXing.OneD.*Writer`), encoded the same way:
/// the same check digits, guards, extended character sets, length limits and bar widths. A module is the narrowest
/// bar or space; the quiet zone is not included.
enum LinearBarcode {
    static func encode(_ symbology: BarcodeSymbology, _ payload: String) throws -> [Bool] {
        switch symbology {
        case .ean13: return try ean13(payload)
        case .ean8: return try ean8(payload)
        case .upcA: return try upcA(payload)
        case .upcE: return try upcE(payload)
        case .code39: return try code39(payload)
        case .code93: return try code93(payload)
        case .codabar: return try codabar(payload)
        case .itf: return try itf(payload)
        case .msi: return try msi(payload)
        case .plessey: return try plessey(payload)
        case .qrCode, .aztec, .dataMatrix, .pdf417, .code128:
            preconditionFailure("\(symbology) is not a bar code of this file")
        }
    }

    /// ZXing's limit for Code 39, 93, 128 and ITF: 80 characters.
    static func checkLength(_ payload: String, name: String, limit: Int = 80) throws {
        let count = payload.count
        guard count <= limit else {
            throw BarcodeError.wrongLength("\(name) holds at most \(limit) characters; this is \(count).")
        }
    }

    // MARK: - Helpers

    /// Bars and spaces of the given widths, starting with a bar (`OneDimensionalCodeWriter.appendPattern`).
    static func pattern(_ widths: [Int], startingWithBar: Bool = true) -> [Bool] {
        var result: [Bool] = []
        var bar = startingWithBar
        for width in widths {
            result += Array(repeating: bar, count: width)
            bar.toggle()
        }
        return result
    }

    /// A string of 1 (bar) and 0 (space) modules.
    static func bits(_ text: String) -> [Bool] {
        text.map { $0 == "1" }
    }

    /// The digits of `payload`, or an error naming the format.
    static func digits(_ payload: String, name: String) throws -> [Int] {
        var result: [Int] = []
        for scalar in payload.unicodeScalars {
            guard scalar.isASCII, let digit = Int(String(scalar)) else {
                throw BarcodeError.invalidCharacters("\(name) takes digits only.")
            }
            result.append(digit)
        }
        return result
    }

    /// The GTIN check digit of EAN and UPC codes (`UPCEANReader.getStandardUPCEANChecksum`): the digits from the right
    /// weighted 3, 1, 3, …
    static func gtinCheckDigit(_ digits: [Int]) -> Int {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            sum += index % 2 == 0 ? digit * 3 : digit
        }
        return (10 - sum % 10) % 10
    }

    /// `digits` with their check digit: computed when there are `length - 1`, checked when there are `length`
    /// (`UPCEANWriter`'s rules).
    static func withCheckDigit(_ digits: [Int], length: Int, name: String,
                               check: ([Int]) -> Int = gtinCheckDigit) throws -> [Int] {
        switch digits.count {
        case length - 1:
            return digits + [check(digits)]
        case length:
            let expected = check(Array(digits.dropLast()))
            guard digits[length - 1] == expected else { throw BarcodeError.wrongCheckDigit(expected: expected) }
            return digits
        default:
            throw BarcodeError.wrongLength("\(name) takes \(length - 1) digits, or \(length) with the check digit.")
        }
    }

    // MARK: - EAN and UPC (ZXing EAN13Writer, EAN8Writer, UPCAWriter, UPCEWriter)

    /// The left-hand odd-parity (L) patterns; R is their complement, G their complement reversed.
    static let lPatterns = ["0001101", "0011001", "0010011", "0111101", "0100011",
                            "0110001", "0101111", "0111011", "0110111", "0001011"]

    static func l(_ digit: Int) -> [Bool] { bits(lPatterns[digit]) }
    static func r(_ digit: Int) -> [Bool] { l(digit).map { !$0 } }
    static func g(_ digit: Int) -> [Bool] { r(digit).reversed() }

    static let sideGuard = bits("101")
    static let middleGuard = bits("01010")

    /// Which of the six left digits of an EAN-13 use G patterns, by the first digit (`EAN13Reader.FIRST_DIGIT_ENCODINGS`).
    static let ean13Parities = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    static func ean13(_ payload: String) throws -> [Bool] {
        let code = try withCheckDigit(digits(payload, name: "EAN-13"), length: 13, name: "EAN-13")
        return ean13Modules(code)
    }

    static func ean13Modules(_ code: [Int]) -> [Bool] {
        let parity = Array(ean13Parities[code[0]])
        var result = sideGuard
        for index in 1...6 {
            result += parity[index - 1] == "G" ? g(code[index]) : l(code[index])
        }
        result += middleGuard
        for index in 7...12 {
            result += r(code[index])
        }
        return result + sideGuard
    }

    static func ean8(_ payload: String) throws -> [Bool] {
        let code = try withCheckDigit(digits(payload, name: "EAN-8"), length: 8, name: "EAN-8")
        var result = sideGuard
        for index in 0...3 { result += l(code[index]) }
        result += middleGuard
        for index in 4...7 { result += r(code[index]) }
        return result + sideGuard
    }

    /// A UPC-A code is an EAN-13 code starting with 0 (`UPCAWriter`).
    static func upcA(_ payload: String) throws -> [Bool] {
        let code = try withCheckDigit(digits(payload, name: "UPC-A"), length: 12, name: "UPC-A")
        return ean13Modules([0] + code)
    }

    /// Which of the six digits of a UPC-E code use G patterns, by number system and check digit
    /// (`UPCEReader.NUMSYS_AND_CHECK_DIGIT_PATTERNS`; a set bit, from the left, is a G pattern).
    static let upcEParities: [[Int]] = [
        [0x38, 0x34, 0x32, 0x31, 0x2C, 0x26, 0x23, 0x2A, 0x29, 0x25],
        [0x07, 0x0B, 0x0D, 0x0E, 0x13, 0x19, 0x1C, 0x15, 0x16, 0x1A],
    ]

    /// The UPC-A code a UPC-E code stands for, without check digit (`UPCEReader.convertUPCEtoUPCA`): number system and
    /// six digits.
    static func upcAExpansion(_ code: [Int]) -> [Int] {
        let d = Array(code[1...6])
        let middle: [Int]
        switch d[5] {
        case 0, 1, 2: middle = [d[0], d[1], d[5], 0, 0, 0, 0, d[2], d[3], d[4]]
        case 3: middle = [d[0], d[1], d[2], 0, 0, 0, 0, 0, d[3], d[4]]
        case 4: middle = [d[0], d[1], d[2], d[3], 0, 0, 0, 0, 0, d[4]]
        default: middle = [d[0], d[1], d[2], d[3], d[4], 0, 0, 0, 0, d[5]]
        }
        return [code[0]] + middle
    }

    static func upcE(_ payload: String) throws -> [Bool] {
        let given = try digits(payload, name: "UPC-E")
        guard given.count == 7 || given.count == 8 else {
            throw BarcodeError.wrongLength("UPC-E takes 7 digits, or 8 with the check digit.")
        }
        guard given[0] == 0 || given[0] == 1 else {
            throw BarcodeError.invalidCharacters("A UPC-E code starts with its number system, 0 or 1.")
        }
        let code = try withCheckDigit(given, length: 8, name: "UPC-E") { gtinCheckDigit(upcAExpansion($0)) }
        let parities = upcEParities[code[0]][code[7]]
        var result = sideGuard
        for index in 1...6 {
            let usesG = (parities >> (6 - index)) & 1 == 1
            result += usesG ? g(code[index]) : l(code[index])
        }
        return result + bits("010101")
    }

    // MARK: - Code 39 (ZXing Code39Writer)

    static let code39Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")
    /// Nine elements per character, bar first; a set bit (from the left) is a wide element (`Code39Reader.CHARACTER_ENCODINGS`).
    static let code39Encodings = [
        0x034, 0x121, 0x061, 0x160, 0x031, 0x130, 0x070, 0x025, 0x124, 0x064,
        0x109, 0x049, 0x148, 0x019, 0x118, 0x058, 0x00D, 0x10C, 0x04C, 0x01C,
        0x103, 0x043, 0x142, 0x013, 0x112, 0x052, 0x007, 0x106, 0x046, 0x016,
        0x181, 0x0C1, 0x1C0, 0x091, 0x190, 0x0D0, 0x085, 0x184, 0x0C4, 0x0A8,
        0x0A2, 0x08A, 0x02A,
    ]
    static let code39Asterisk = 0x094

    static func code39Character(_ encoding: Int) -> [Bool] {
        // ZXing draws wide elements 2 modules wide.
        pattern((0..<9).map { encoding & (1 << (8 - $0)) == 0 ? 1 : 2 })
    }

    static func code39(_ payload: String) throws -> [Bool] {
        try checkLength(payload, name: "Code 39")
        var text = Array(payload)
        if text.contains(where: { !code39Alphabet.contains($0) }) {
            text = try code39FullASCII(payload)
            try checkLength(String(text), name: "Code 39 (full ASCII)")
        }
        var result = code39Character(code39Asterisk) + [false]
        for character in text {
            guard let index = code39Alphabet.firstIndex(of: character) else { continue }
            result += code39Character(code39Encodings[index]) + [false]
        }
        return result + code39Character(code39Asterisk)
    }

    /// Code 39 full ASCII: other characters as pairs of the basic ones (`Code39Writer.tryToConvertToExtendedMode`).
    static func code39FullASCII(_ payload: String) throws -> [Character] {
        var result: [Character] = []
        for scalar in payload.unicodeScalars {
            let c = Int(scalar.value)
            func pair(_ shift: Character, _ base: Int, _ offset: Int) {
                result += [shift, Character(UnicodeScalar(UInt8(base + offset)))]
            }
            switch c {
            case 0: result += ["%", "U"]
            case 32, 45, 46: result.append(Character(scalar))
            case 64: result += ["%", "V"]
            case 96: result += ["%", "W"]
            case 1...26: pair("$", 65, c - 1)
            case 27...31: pair("%", 65, c - 27)
            case 33...44, 47, 58: pair("/", 65, c - 33)
            case 48...57: result.append(Character(scalar))
            case 59...63: pair("%", 70, c - 59)
            case 65...90: result.append(Character(scalar))
            case 91...95: pair("%", 75, c - 91)
            case 97...122: pair("+", 65, c - 97)
            case 123...127: pair("%", 80, c - 123)
            default:
                throw BarcodeError.invalidCharacters("Code 39 holds only ASCII characters.")
            }
        }
        return result
    }

    // MARK: - Code 93 (ZXing Code93Writer)

    /// a, b, c and d are the shift characters ($), (%), (/) and (+); * is the start and stop character.
    static let code93Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%abcd*")
    /// Nine modules per character, from the left (`Code93Reader.CHARACTER_ENCODINGS`).
    static let code93Encodings = [
        0x114, 0x148, 0x144, 0x142, 0x128, 0x124, 0x122, 0x150, 0x112, 0x10A,
        0x1A8, 0x1A4, 0x1A2, 0x194, 0x192, 0x18A, 0x168, 0x164, 0x162, 0x134,
        0x11A, 0x158, 0x14C, 0x146, 0x12C, 0x116, 0x1B4, 0x1B2, 0x1AC, 0x1A6,
        0x196, 0x19A, 0x16C, 0x166, 0x136, 0x13A,
        0x12E, 0x1D4, 0x1D2, 0x1CA, 0x16E, 0x176, 0x1AE,
        0x126, 0x1DA, 0x1D6, 0x132, 0x15E,
    ]

    static func code93Character(_ index: Int) -> [Bool] {
        let encoding = code93Encodings[index]
        return (0..<9).map { encoding & (1 << (8 - $0)) != 0 }
    }

    /// The index of a check character: the weighted sum from the right, weights 1 up to `maxWeight` and again
    /// (`Code93Writer.computeChecksumIndex`).
    static func code93Check(_ indexes: [Int], maxWeight: Int) -> Int {
        var weight = 1
        var total = 0
        for index in indexes.reversed() {
            total += index * weight
            weight = weight == maxWeight ? 1 : weight + 1
        }
        return total % 47
    }

    /// The characters of `payload` with their two check characters C and K, as alphabet indexes.
    static func code93Indexes(_ payload: String) throws -> [Int] {
        let extended = try code93Extended(payload)
        try checkLength(String(extended), name: "Code 93")
        var indexes = extended.compactMap { code93Alphabet.firstIndex(of: $0) }
        indexes.append(code93Check(indexes, maxWeight: 20))
        indexes.append(code93Check(indexes, maxWeight: 15))
        return indexes
    }

    static func code93(_ payload: String) throws -> [Bool] {
        let star = code93Alphabet.count - 1
        var result = code93Character(star)
        for index in try code93Indexes(payload) {
            result += code93Character(index)
        }
        // The stop character and a termination bar.
        return result + code93Character(star) + [true]
    }

    /// Code 93 full ASCII: other characters as a shift character and a letter (`Code93Writer.convertToExtended`).
    static func code93Extended(_ payload: String) throws -> [Character] {
        var result: [Character] = []
        for scalar in payload.unicodeScalars {
            let c = Int(scalar.value)
            func pair(_ shift: Character, _ base: Int, _ offset: Int) {
                result += [shift, Character(UnicodeScalar(UInt8(base + offset)))]
            }
            switch c {
            case 0: result += ["b", "U"]
            case 1...26: pair("a", 65, c - 1)
            case 27...31: pair("b", 65, c - 27)
            case 32, 36, 37, 43: result.append(Character(scalar))
            case 33...44: pair("c", 65, c - 33)
            case 45...57: result.append(Character(scalar))
            case 58: result += ["c", "Z"]
            case 59...63: pair("b", 70, c - 59)
            case 64: result += ["b", "V"]
            case 65...90: result.append(Character(scalar))
            case 91...95: pair("b", 75, c - 91)
            case 96: result += ["b", "W"]
            case 97...122: pair("d", 65, c - 97)
            case 123...127: pair("b", 80, c - 123)
            default:
                throw BarcodeError.invalidCharacters("Code 93 holds only ASCII characters.")
            }
        }
        return result
    }

    // MARK: - Codabar (ZXing CodaBarWriter)

    static let codabarAlphabet = Array("0123456789-$:/.+ABCD")
    /// Seven elements per character, bar first; a set bit (from the left) is a wide element
    /// (`CodaBarReader.CHARACTER_ENCODINGS`).
    static let codabarEncodings = [0x003, 0x006, 0x009, 0x060, 0x012, 0x042, 0x021, 0x024, 0x030, 0x048,
                                   0x00C, 0x018, 0x045, 0x051, 0x054, 0x015, 0x01A, 0x029, 0x00B, 0x00E]
    static let codabarGuards: [Character] = ["A", "B", "C", "D"]
    /// T, N, * and E are other names of the guards A, B, C and D.
    static let codabarAlternateGuards: [Character] = ["T", "N", "*", "E"]

    /// The text with its start and stop characters: A…A when it has none (`CodaBarWriter.encode`).
    static func codabarText(_ payload: String) throws -> [Character] {
        let text = Array(payload.uppercased())
        let invalidGuards = BarcodeError.invalidCharacters("Codabar starts and ends with A, B, C or D (or T, N, *, E), or with neither.")
        guard text.count >= 2, let first = text.first, let last = text.last else { return ["A"] + text + ["A"] }
        if codabarGuards.contains(first) {
            guard codabarGuards.contains(last) else { throw invalidGuards }
            return text
        }
        if codabarAlternateGuards.contains(first) {
            guard codabarAlternateGuards.contains(last) else { throw invalidGuards }
            return text
        }
        guard !codabarGuards.contains(last), !codabarAlternateGuards.contains(last) else { throw invalidGuards }
        return ["A"] + text + ["A"]
    }

    static func codabar(_ payload: String) throws -> [Bool] {
        var text = try codabarText(payload)
        let inner = text.dropFirst().dropLast()
        guard inner.allSatisfy({ "0123456789-$:/.+".contains($0) }) else {
            throw BarcodeError.invalidCharacters("Codabar holds digits and - $ : / . + between its start and stop characters.")
        }
        for (end, alternate) in [(0, text[0]), (text.count - 1, text[text.count - 1])] {
            if let index = codabarAlternateGuards.firstIndex(of: alternate) { text[end] = codabarGuards[index] }
        }
        var result: [Bool] = []
        for (index, character) in text.enumerated() {
            guard let position = codabarAlphabet.firstIndex(of: character) else { continue }
            let encoding = codabarEncodings[position]
            // ZXing draws wide elements 2 modules wide, with a narrow space between the characters.
            result += pattern((0..<7).map { encoding & (1 << (6 - $0)) == 0 ? 1 : 2 })
            if index < text.count - 1 { result.append(false) }
        }
        return result
    }

    // MARK: - ITF (ZXing ITFWriter)

    /// Narrow (1) and wide (3) elements of each digit (`ITFWriter.PATTERNS`).
    static let itfPatterns = [[1, 1, 3, 3, 1], [3, 1, 1, 1, 3], [1, 3, 1, 1, 3], [3, 3, 1, 1, 1], [1, 1, 3, 1, 3],
                              [3, 1, 3, 1, 1], [1, 3, 3, 1, 1], [1, 1, 1, 3, 3], [3, 1, 1, 3, 1], [1, 3, 1, 3, 1]]

    static func itf(_ payload: String) throws -> [Bool] {
        let code = try digits(payload, name: "ITF")
        guard code.count % 2 == 0 else {
            throw BarcodeError.wrongLength("ITF takes an even number of digits; this is \(code.count).")
        }
        try checkLength(payload, name: "ITF")
        var result = pattern([1, 1, 1, 1])
        for pair in stride(from: 0, to: code.count, by: 2) {
            // The first digit is in the bars, the second in the spaces between them.
            let bars = itfPatterns[code[pair]]
            let spaces = itfPatterns[code[pair + 1]]
            result += pattern((0..<5).flatMap { [bars[$0], spaces[$0]] })
        }
        return result + pattern([3, 1, 1])
    }

    // MARK: - MSI (ZXing MSIWriter)

    /// The MSI Mod 10 check digit: every other digit from the right doubled, the digits of it all added.
    static func msiCheckDigit(_ digits: [Int]) -> Int {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 0 {
                let doubled = digit * 2
                sum += doubled / 10 + doubled % 10
            } else {
                sum += digit
            }
        }
        return (10 - sum % 10) % 10
    }

    /// Unlike ZXing's MSIWriter, the Mod 10 check digit is added: scanners expect it, and without it they read the code
    /// wrong.
    static func msi(_ payload: String) throws -> [Bool] {
        var code = try digits(payload, name: "MSI")
        code.append(msiCheckDigit(code))
        var result = bits("110")
        for digit in code {
            for bit in stride(from: 3, through: 0, by: -1) {
                result += bits((digit >> bit) & 1 == 1 ? "110" : "100")
            }
        }
        return result + bits("1001")
    }

    // MARK: - Plessey (ZXing.Net PlesseyWriter)

    static let plesseyAlphabet = Array("0123456789ABCDEF")
    /// ZXing.Net draws a bit 25 units wide: 0 as a 5 unit bar and a 20 unit space, 1 as 14 and 11. Here a module is
    /// 5 units, so 0 is a 1 module bar and 4 spaces, 1 is 3 and 2.
    static let plesseyZero = [1, 4]
    static let plesseyOne = [3, 2]
    /// x⁸ + x⁷ + x⁶ + x⁵ + x³ + 1 (`PlesseyWriter.crcGrid`).
    static let plesseyCRCGrid = [1, 1, 1, 1, 0, 1, 0, 0, 1]

    /// The 8 check bits of the data bits (each hex digit lowest bit first).
    static func plesseyCRC(_ dataBits: [Int]) -> [Int] {
        var buffer = dataBits + Array(repeating: 0, count: 8)
        for i in 0..<dataBits.count where buffer[i] != 0 {
            for j in 0..<9 { buffer[i + j] ^= plesseyCRCGrid[j] }
        }
        return Array(buffer.suffix(8))
    }

    static func plessey(_ payload: String) throws -> [Bool] {
        let text = Array(payload.uppercased())
        var dataBits: [Int] = []
        for character in text {
            guard let value = plesseyAlphabet.firstIndex(of: character) else {
                throw BarcodeError.invalidCharacters("Plessey takes digits and the letters A to F.")
            }
            dataBits += (0..<4).map { (value >> $0) & 1 }
        }
        func bit(_ value: Int) -> [Bool] { pattern(value == 0 ? plesseyZero : plesseyOne) }
        // The start pattern is the bits 1101.
        var result = [1, 1, 0, 1].flatMap(bit)
        result += dataBits.flatMap(bit)
        result += plesseyCRC(dataBits).flatMap(bit)
        // A termination bar, then the end pattern starting with a space (ZXing.Net: 20 5 20 5 14 11 14 11 units).
        result += pattern([5])
        return result + pattern([4, 1, 4, 1, 3, 2, 3, 2], startingWithBar: false)
    }
}

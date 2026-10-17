// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage
import Foundation

/// The modules of a code without its quiet zone, the top row first; a bar code has one row (upstream ZXing's
/// `BitMatrix`).
public struct BarcodeMatrix: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Row by row, true for a dark module.
    public let modules: [Bool]

    public init(width: Int, height: Int, modules: [Bool]) {
        precondition(width >= 0 && height >= 0 && modules.count == width * height, "matrix size")
        self.width = width
        self.height = height
        self.modules = modules
    }

    /// A bar code: one row of bars (true) and spaces.
    public init(row: [Bool]) {
        self.init(width: row.count, height: 1, modules: row)
    }

    public subscript(x: Int, y: Int) -> Bool {
        modules[y * width + x]
    }

    /// The row as a string of 1 (bar) and 0 (space), for tests and logs.
    public func row(_ y: Int) -> String {
        String(modules[(y * width)..<((y + 1) * width)].map { $0 ? "1" : "0" })
    }
}

/// Why a text can't be made into a code (upstream shows ZXing's exception message under the preview).
public enum BarcodeError: Error, Equatable, LocalizedError {
    /// There is nothing to encode.
    case empty
    /// The text has characters the format can't hold; the message says what it takes.
    case invalidCharacters(String)
    /// The text is too short or too long for the format; the message says what it takes.
    case wrongLength(String)
    /// The last digit is not the right check digit.
    case wrongCheckDigit(expected: Int)
    /// More than the biggest code of the format holds.
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .empty: return "There is nothing to encode."
        case .invalidCharacters(let message), .wrongLength(let message): return message
        case .wrongCheckDigit(let expected): return "The check digit is wrong: the last digit should be \(expected)."
        case .tooLong: return "The text is too long for this code."
        }
    }
}

/// Makes the module matrix of a code. QR, Aztec, PDF-417 and Code 128 come from Core Image (with ZXing's default
/// error correction, as upstream's `ZxingBarcodeGenerator.Generate` uses ZXing); the other formats are encoded here.
public enum BarcodeGenerator {
    /// The matrix of `payload` in `symbology`, without quiet zone.
    public static func matrix(_ symbology: BarcodeSymbology, payload: String) throws -> BarcodeMatrix {
        guard !payload.isEmpty else { throw BarcodeError.empty }
        switch symbology {
        case .qrCode:
            // ZXing's QRCodeWriter uses level L unless told otherwise.
            return try coreImage("CIQRCodeGenerator", Data(payload.utf8), border: CoreImageBorder.qrCode,
                                 ["inputCorrectionLevel": "L"])
        case .aztec:
            // ZXing's AztecWriter: 33 % error correction, layers chosen to fit.
            return try coreImage("CIAztecCodeGenerator", Data(payload.utf8), border: CoreImageBorder.aztec,
                                 ["inputCorrectionLevel": 33])
        case .pdf417:
            // ZXing's PDF417Writer: error correction level 2. Core Image draws every row 3 modules tall, the usual height.
            return try coreImage("CIPDF417BarcodeGenerator", Data(payload.utf8), border: CoreImageBorder.pdf417,
                                 ["inputCorrectionLevel": 2])
        case .code128:
            return try code128(payload)
        case .dataMatrix:
            return try DataMatrixEncoder.matrix(payload)
        case .code39, .code93, .ean13, .ean8, .upcA, .upcE, .codabar, .itf, .msi, .plessey:
            return BarcodeMatrix(row: try LinearBarcode.encode(symbology, payload))
        }
    }

    /// The quiet zone Core Image draws around its codes, in modules (measured; `BarcodeGeneratorTests` checks it).
    enum CoreImageBorder {
        static let qrCode = 1
        static let aztec = 2
        static let pdf417 = 2
    }

    /// ZXing's Code128Writer: ASCII, 1 to 80 characters. Core Image picks the code sets.
    static func code128(_ payload: String) throws -> BarcodeMatrix {
        guard payload.unicodeScalars.allSatisfy(\.isASCII) else {
            throw BarcodeError.invalidCharacters("Code 128 holds only ASCII characters (no accents or symbols beyond ASCII).")
        }
        try LinearBarcode.checkLength(payload, name: "Code 128")
        let matrix = try coreImage("CICode128BarcodeGenerator", Data(payload.utf8), border: 0,
                                   ["inputQuietSpace": 0, "inputBarcodeHeight": 1])
        // One row is all that matters (Core Image may repeat it).
        return BarcodeMatrix(row: Array(matrix.modules.prefix(matrix.width)))
    }

    /// The modules of a Core Image code generator's output (one pixel per module), with its own quiet zone removed.
    static func coreImage(_ name: String, _ message: Data, border: Int, _ parameters: [String: Any]) throws -> BarcodeMatrix {
        var all = parameters
        all["inputMessage"] = message
        guard let output = CIFilter(name: name, parameters: all)?.outputImage else { throw BarcodeError.tooLong }
        let extent = output.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 2 * border, height > 2 * border, width * height <= 1 << 22 else { throw BarcodeError.tooLong }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        AnnotationRenderer.ciContext.render(output, toBitmap: &pixels, rowBytes: width * 4, bounds: extent, format: .RGBA8,
                                            colorSpace: AnnotationRenderer.sRGB)
        let innerWidth = width - 2 * border
        let innerHeight = height - 2 * border
        var modules: [Bool] = []
        modules.reserveCapacity(innerWidth * innerHeight)
        for y in border..<(height - border) {
            for x in border..<(width - border) {
                modules.append(pixels[(y * width + x) * 4] < 128)
            }
        }
        return BarcodeMatrix(width: innerWidth, height: innerHeight, modules: modules)
    }
}

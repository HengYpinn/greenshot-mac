// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Vision

/// Upstream `ProcessorExecutionStep`: on the Mac the only capture processor is OCR (Vision). It runs when the node asks
/// for it (`ProcessorMode` OCR, an OCR id in `ProcessorIds`, or `ProcessorMode` Selected with `RunOcr`), or else when
/// the settings run OCR on every capture. Window title fixes and plug-in processors have no Mac counterpart.
struct ProcessorsExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("Processors skipped: there is no image.")
            return
        }
        context.state = .processing
        let mode = step.string("ProcessorMode")?.trimmingCharacters(in: .whitespaces) ?? ""
        let ids = step.strings("ProcessorIds") ?? []
        let explicit = recipeEquals(mode, "OCR") || ids.contains { $0.lowercased().contains("ocr") }
            || (recipeEquals(mode, "Selected") && (step.bool("RunOcr") ?? true))
        // Upstream filters the processors by `Timing` (ProcessorExecutionStep.cs): the OCR processor is PreSelection, which
        // on the Mac is the capture screen's own recognition, so the settings path runs only for Timing Any (or none).
        let timing = step.string("Timing")?.trimmingCharacters(in: .whitespaces) ?? ""
        let anyTiming = timing.isEmpty || recipeEquals(timing, "Any")
        let fromSettings = mode.isEmpty && ids.isEmpty && anyTiming
            && context.environment.configValue("alwaysRunOCROnCapture")?.asBool == true
        guard explicit || fromSettings else {
            context.log("Processors: nothing to run.")
            return
        }
        let language = context.environment.configValue("ocrLanguage")?.asString ?? ""
        let lines: [RecognizedLine]
        do {
            lines = try await TextRecognizer.recognizeLines(in: payload.flattened() ?? payload.image, language: language)
        } catch {
            log.error("OCR of recipe '\(context.recipe.id)' failed.", error: error)
            context.log("Warning: OCR failed: \(error.localizedDescription)")
            return
        }
        guard !lines.isEmpty else {
            context.log("OCR found no text.")
            return
        }
        let text = lines.map(\.text).joined(separator: "\n")
        payload.extractedText = text
        context.payload = payload
        for name in ["OcrText", "Text", "CommandResult"] { context[variable: name] = .string(text) }
        context.log("OCR extracted \(lines.count) line(s) of text.")
    }
}

/// Upstream Zxing plug-in `ZxingStep`, with Vision's barcode detection: the decoded text of every barcode on the
/// capture, one per line, also as the extracted text.
struct BarcodeScanExecutor: RecipeStepExecutor {
    let clipboard: (any RecipeClipboardWriting)?

    /// Everything Vision reads (ZXing reads 1D and 2D codes too).
    static let symbologies: [VNBarcodeSymbology] = [.qr, .aztec, .dataMatrix, .pdf417, .code128, .code39, .code93, .ean8, .ean13, .upce,
                                                    .itf14, .i2of5]

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("BarcodeScan: there is no image to scan.")
            return
        }
        let found: [DetectedBarcode]
        do {
            found = try await BarcodeDetector.detect(in: payload.flattened() ?? payload.image, symbologies: Self.symbologies)
        } catch {
            log.warn("Barcode scan of recipe '\(context.recipe.id)' failed.", error: error)
            context.log("Warning: barcode scan failed: \(error.localizedDescription)")
            return
        }
        guard !found.isEmpty else {
            context.log("BarcodeScan: no QR codes or barcodes found.")
            return
        }
        let text = found.map(\.payload).joined(separator: "\n")
        payload.extractedText = text
        context.payload = payload
        context[variable: "Zxing.DecodedText"] = .string(text)
        context[variable: "Barcode.Text"] = .string(text)
        context[variable: "Barcode.Format"] = .string(found.map { Self.zxingFormat($0.symbology) }.joined(separator: "\n"))
        if let variable = step.string("SetVariable")?.trimmingCharacters(in: .whitespaces), !variable.isEmpty {
            context[variable: variable] = .string(text)
        }
        if step.bool("CopyToClipboard") ?? false {
            if let clipboard {
                await clipboard.copy(text: text)
            } else {
                context.log("BarcodeScan: no clipboard to copy to.")
            }
        }
        context.log("Detected \(found.count) barcode(s).")
    }

    /// The ZXing name of a Vision symbology ("QR" -> "QR_CODE").
    static func zxingFormat(_ symbology: String) -> String {
        let names: [String: String] = ["qr": "QR_CODE", "microqr": "QR_CODE", "aztec": "AZTEC", "datamatrix": "DATA_MATRIX",
                                       "pdf417": "PDF_417", "micropdf417": "PDF_417", "code128": "CODE_128", "code39": "CODE_39",
                                       "code39checksum": "CODE_39", "code39fullascii": "CODE_39", "code39fullasciichecksum": "CODE_39",
                                       "code93": "CODE_93", "code93i": "CODE_93", "ean8": "EAN_8", "ean13": "EAN_13", "upce": "UPC_E",
                                       "itf14": "ITF", "i2of5": "ITF", "i2of5checksum": "ITF", "codabar": "CODABAR", "gs1databar": "RSS_14"]
        return names[symbology.lowercased()] ?? symbology.uppercased()
    }
}

private let log = Log("Recipes")

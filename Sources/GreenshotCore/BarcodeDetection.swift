// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Vision

/// A QR code (or other barcode) found in an image, in pixels of that image, origin top left.
public struct DetectedBarcode: Equatable, Sendable {
    public var payload: String
    public var bounds: CGRect
    /// e.g. "QR", "Aztec", "EAN13".
    public var symbology: String

    public init(payload: String, bounds: CGRect, symbology: String) {
        self.payload = payload
        self.bounds = bounds
        self.symbology = symbology
    }

    /// The payload as a URL when it is one (http, https, mailto, …).
    public var url: URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel", "sms", "ftp"].contains(scheme) else {
            return nil
        }
        return url
    }
}

/// Barcode detection with the Vision framework: the Mac's stand-in for upstream's Zxing plugin
/// (`Greenshot.Plugin.Zxing/Processing/ZxingCaptureProcessor.cs`).
public enum BarcodeDetector {
    /// What `detect` looks for unless told otherwise.
    public static let defaultSymbologies: [VNBarcodeSymbology] = [.qr, .aztec, .dataMatrix, .pdf417]

    /// The barcodes in `image`.
    ///
    /// Blocks the calling thread until Vision is done. Call it only on a GCD queue or a thread of your own, never in a
    /// task or an async function (Vision may wait for a thread of Swift's cooperative pool, see
    /// `TextRecognizer.recognizeLines`): there, `await` the async overload.
    public static func detect(in image: CGImage, symbologies: [VNBarcodeSymbology] = defaultSymbologies) throws -> [DetectedBarcode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            let bounds = TextRecognizer.pixelRect(observation.boundingBox, width: width, height: height)
            return DetectedBarcode(payload: payload, bounds: bounds, symbology: observation.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""))
        }
    }

    /// The barcodes in `image`, for tasks and async functions: Vision runs on a queue of its own and the task's thread
    /// is free while it waits.
    public static func detect(in image: CGImage, symbologies: [VNBarcodeSymbology] = defaultSymbologies) async throws -> [DetectedBarcode] {
        try await VisionQueue.run { try detect(in: image, symbologies: symbologies) }
    }
}

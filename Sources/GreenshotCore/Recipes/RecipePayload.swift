// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The capture a flow works on (upstream `ICapturePayload`: raw capture + surface + extracted text). A value: a parallel
/// branch gets its own copy. `annotations` are the surface's elements, still editable when the Editor destination opens
/// it (RAPP builds an `EditorDocument` from image, scale, title and annotations).
///
/// Units: recipe geometry (annotation left/top/width/height/offsets/margins, effect sizes, `payload.width`) is in points,
/// i.e. upstream's pixels at 96 DPI, multiplied by `scale` to get image pixels; the same rule as `ImageEffects`.
public struct RecipePayload: @unchecked Sendable {
    public var image: CGImage
    /// Pixels per point of the capture (2 on a Retina display).
    public var scale: CGFloat
    public var annotations: [Annotation] = []
    /// OCR or barcode text (upstream `ExtractedText`).
    public var extractedText: String?
    /// The window title (upstream `CaptureDetails.Title`).
    public var title: String
    public var captureDate: Date
    /// The file it was loaded from or saved to (upstream `CaptureDetails.Filename`).
    public var fileURL: URL?
    /// The source type that acquired it ("Region", "Window", "File", ...).
    public var sourceType: String?
    /// Upstream `ICapturePayload.Metadata` (`payload.<key>` falls back to it).
    public var metadata: [String: JSONValue] = [:]
    /// What the app keeps with the capture for its own steps (the mouse pointer, the frozen screens the selection needs);
    /// copied by reference with the payload.
    public var attachments: [String: any Sendable] = [:]

    public init(image: CGImage, scale: CGFloat, title: String, captureDate: Date = Date()) {
        self.image = image
        self.scale = scale
        self.title = title
        self.captureDate = captureDate
    }

    public var metrics: PayloadMetrics {
        let pixelsPerPoint = scale > 0 ? Double(scale) : 1
        return PayloadMetrics(width: Double(image.width) / pixelsPerPoint, height: Double(image.height) / pixelsPerPoint,
                              extractedText: extractedText ?? "", title: title, filename: fileURL?.path ?? "", metadata: metadata)
    }

    /// The image with the annotations drawn on it (`AnnotationRenderer.flatten`).
    public func flattened() -> CGImage? {
        annotations.isEmpty ? image : AnnotationRenderer.flatten(base: image, annotations: annotations, scale: scale)
    }
}

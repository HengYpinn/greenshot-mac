// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The new slide the first PowerPoint script made (`OfficeScripts.powerPointSlide`).
public struct PowerPointSlide: Equatable, Sendable {
    public var presentationName: String
    public var index: Int
    public var slideSize: CGSize
    /// The layout's picture placeholder (its second shape), when the layout has one.
    public var placeholder: CGRect?

    public init(presentationName: String, index: Int, slideSize: CGSize, placeholder: CGRect?) {
        self.presentationName = presentationName
        self.index = index
        self.slideSize = slideSize
        self.placeholder = placeholder
    }

    /// Parses the script's tab-separated answer.
    public init?(output: String) {
        let fields = output.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard fields.count >= 4, !fields[0].isEmpty else { return nil }
        let numbers = fields.dropFirst().map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let index = numbers[0], let width = numbers[1], let height = numbers[2] else { return nil }
        presentationName = fields[0]
        self.index = index
        slideSize = CGSize(width: width, height: height)
        if numbers.count >= 7, let x = numbers[3], let y = numbers[4], let w = numbers[5], let h = numbers[6], w > 0, h > 0 {
            placeholder = CGRect(x: x, y: y, width: w, height: h)
        } else {
            placeholder = nil
        }
    }
}

/// Where the pictures go in Office documents, and how they are handed over.
public enum OfficeLayout {
    /// The picture's place on a slide: its own size, shrunk to fit the layout's picture placeholder (or the slide) with
    /// the aspect ratio kept, centred in it (upstream `PowerpointExporter.AddPictureToPresentation` centres the picture
    /// and shrinks it to the placeholder).
    public static func pictureFrame(imageSize: CGSize, slide: PowerPointSlide) -> CGRect {
        let area = slide.placeholder ?? CGRect(origin: .zero, size: slide.slideSize)
        return fit(imageSize, in: area)
    }

    /// `size` scaled down (never up) to fit `area`, centred in it.
    public static func fit(_ size: CGSize, in area: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else {
            return CGRect(origin: area.origin, size: size)
        }
        let widthScale = area.width / size.width
        let heightScale = area.height / size.height
        let scale = min(1, min(widthScale, heightScale))
        let width = size.width * scale
        let height = size.height * scale
        let x = area.midX - width / 2
        let y = area.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The size of the capture in points (its pixels at its scale), which Office takes as the picture's size.
    public static func pointSize(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> CGSize {
        let factor = scale > 0 ? scale : 1
        return CGSize(width: CGFloat(pixelWidth) / factor, height: CGFloat(pixelHeight) / factor)
    }

    /// The format of the file Office gets: the output format when Office can insert it (upstream uses the output
    /// format, but never the .greenshot one), else PNG.
    public static func fileFormat(for outputFormat: ImageFormat) -> ImageFormat {
        switch outputFormat {
        case .png, .jpg, .gif, .tiff, .bmp: return outputFormat
        default: return .png
        }
    }

    /// The attachment's name from the capture's title (upstream `OutlookDestination`: trimmed, only letters, digits,
    /// `_` and spaces, "Greenshot Capture" when nothing is left).
    public static func attachmentName(title: String) -> String {
        let kept = title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.filter { scalar in
            scalar == " " || scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
        let name = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Greenshot Capture" : name
    }
}

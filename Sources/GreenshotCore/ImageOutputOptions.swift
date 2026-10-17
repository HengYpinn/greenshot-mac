// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// How an image is written: upstream `SurfaceOutputSettings` (`Greenshot.Base/Interfaces/Plugin/SurfaceOutputSettings.cs`).
public struct ImageOutputOptions: Equatable, Sendable {
    public var format: ImageFormat
    /// 1...100, used by JPEG (upstream `JPGQuality`).
    public var jpegQuality: Int
    /// The capture's pixels per point, written as the resolution (72 dpi × scale).
    public var scale: CGFloat
    /// Upstream `ReduceColors` (`OutputFileReduceColors`): at most `reduceColorsTo` colours.
    public var reduceColors: Bool
    /// Upstream `OutputFileReduceColorsTo`, 2...256.
    public var reduceColorsTo: Int
    /// Upstream `OutputFileAutoReduceColors`.
    public var autoReduceColors: Bool
    /// The page of the PDF format (upstream `IPdfConfiguration`).
    public var pdf: PDFSettings
    /// The PDF document title; empty uses the file name.
    public var title: String

    public init(format: ImageFormat, jpegQuality: Int = 80, scale: CGFloat = 1, reduceColors: Bool = false,
                reduceColorsTo: Int = 256, autoReduceColors: Bool = false, pdf: PDFSettings = PDFSettings(),
                title: String = "") {
        self.format = format
        self.jpegQuality = jpegQuality
        self.scale = scale
        self.reduceColors = reduceColors
        self.reduceColorsTo = reduceColorsTo
        self.autoReduceColors = autoReduceColors
        self.pdf = pdf
        self.title = title
    }

    /// Settings › Output for `format` (the output format when nil).
    public init(settings: AppSettings, format: ImageFormat? = nil, scale: CGFloat = 1, title: String = "") {
        self.init(format: format ?? settings.outputFormat, jpegQuality: settings.jpegQuality, scale: scale,
                  reduceColors: settings.reduceColors, reduceColorsTo: settings.reduceColorsTo,
                  autoReduceColors: settings.autoReduceColors, pdf: settings.pdf, title: title)
    }
}

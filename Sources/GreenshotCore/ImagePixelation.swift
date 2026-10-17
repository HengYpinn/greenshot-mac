// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage.CIFilterBuiltins
import Foundation

/// Pixelate of the obfuscate element (upstream `Greenshot.Editor/Drawing/Filters/PixelizationFilter.cs`).
public enum ImagePixelation {
    /// `image` in blocks of `blockSize` pixels; `element` is the obfuscate element's id (the secret noise that makes the
    /// pixelation irreversible is keyed by it).
    public static func pixelated(_ image: CGImage, blockSize: CGFloat, element: UUID) -> CGImage? {
        AnnotationRenderer.filtered(image) { input in
            let filter = CIFilter.pixellate()
            filter.inputImage = input
            filter.scale = Float(max(blockSize, 1))
            filter.center = .zero
            return filter.outputImage ?? input
        }
    }
}

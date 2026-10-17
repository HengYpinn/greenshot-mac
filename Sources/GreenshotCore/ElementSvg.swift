// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// SVG pictures (upstream `SvgFileFormatHandler`, `SvgContainer`). E1 phase 2.
public enum ElementSvg {
    /// An SVG file drawn into a picture for opening it as a capture; nil when `url` is not an SVG.
    public static func rasterizedFile(_ url: URL) -> (image: CGImage, scale: CGFloat)? { nil }
}

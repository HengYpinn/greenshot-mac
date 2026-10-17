// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Where an editor window opens and how large it is (upstream `ImageEditorForm` `ApplyStoredPlacement`,
/// `GetOptimalWindowSize` and `Greenshot.Editor/Configuration/EditorConfigurationHelper.cs`). Rectangles are in AppKit
/// screen coordinates (origin bottom left); screens are their visible frames.
public enum EditorWindowPlacement {
    /// The smallest window sized to a capture (upstream `GetOptimalWindowSize`: 650 × 530).
    public static let minimumFittedSize = CGSize(width: 650, height: 530)
    /// How much of the title bar must be on a screen for a remembered frame to be used again.
    static let visibleTitleBar = CGSize(width: 60, height: 8)
    static let titleBarHeight: CGFloat = 24

    /// Whether a remembered window frame can be used again: enough of its title bar is on a screen to drag it. When
    /// the screens changed it isn't, and the placement is reset (upstream checks the screen bounds, BUG-1812).
    public static func isUsable(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - titleBarHeight, width: frame.width, height: titleBarHeight)
        return screens.contains { screen in
            let part = screen.intersection(titleBar)
            return !part.isNull && part.width >= min(visibleTitleBar.width, frame.width) && part.height >= visibleTitleBar.height
        }
    }

    /// The screen that shows most of `frame`, if any part of it is on a screen.
    public static func screen(for frame: CGRect, screens: [CGRect]) -> CGRect? {
        let candidates = screens.map { (screen: $0, part: $0.intersection(frame)) }.filter { !$0.part.isNull }
        return candidates.max { $0.part.width * $0.part.height < $1.part.width * $1.part.height }?.screen
    }

    /// The window frame that shows `contentSize` (upstream `GetOptimalWindowSize`): the content plus `chrome` (bars and
    /// borders), at least `minimum`, at most the screen. Its top left stays at `topLeft` (upstream opens where the last
    /// editor was), else it is centred; a window that would stick out is moved onto the screen instead of being made
    /// smaller.
    public static func fittedFrame(contentSize: CGSize, chrome: CGSize, minimum: CGSize = minimumFittedSize,
                                   topLeft: CGPoint?, screen: CGRect) -> CGRect {
        let width = min(max(contentSize.width + chrome.width, minimum.width), screen.width)
        let height = min(max(contentSize.height + chrome.height, minimum.height), screen.height)
        let origin: CGPoint
        if let topLeft {
            origin = CGPoint(x: topLeft.x, y: topLeft.y - height)
        } else {
            origin = CGPoint(x: screen.midX - width / 2, y: screen.midY - height / 2)
        }
        return moved(CGRect(origin: origin, size: CGSize(width: width, height: height)), onto: screen)
    }

    /// `frame` moved so it lies on `screen`; larger than the screen it is made as large as the screen.
    public static func moved(_ frame: CGRect, onto screen: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(frame.width, screen.width)
        result.size.height = min(frame.height, screen.height)
        result.origin.x = min(max(frame.minX, screen.minX), screen.maxX - result.width)
        // Keep the title bar: when the window is too low it moves up, when too high it moves down.
        result.origin.y = min(max(frame.minY, screen.minY), screen.maxY - result.height)
        return result
    }

    /// A white image for File › New Image (upstream `ImageEditorForm()` with `DefaultEditorSize`), `size` points at
    /// `scale` pixels per point.
    public static func blankImage(points size: CGSize, scale: CGFloat) -> CGImage? {
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

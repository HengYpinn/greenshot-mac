// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A Region argument of an AI tool or a command line recipe: "x,y,width,height" in screen coordinates (upstream
/// `CommandlineArgumentBinder.TryParseRegion`). On the Mac these are Quartz global points with the origin at the top
/// left of the main display, the space of `list_windows`.
public struct AIToolRegion: Equatable, Sendable {
    public var rect: CGRect

    public init?(text: String) {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        let x = CGFloat(numbers[0])
        let y = CGFloat(numbers[1])
        let width = CGFloat(numbers[2])
        let height = CGFloat(numbers[3])
        rect = CGRect(x: x, y: y, width: width, height: height)
    }

    /// The argument text of a region given as an array `[x, y, width, height]` of numbers (upstream
    /// `RecipeTool.ToArgumentValue`).
    public static func text(of numbers: [Double]) -> String {
        numbers.map { $0.rounded() == $0 && abs($0) < 9.0e15 ? String(Int64($0)) : String($0) }.joined(separator: ",")
    }
}

/// The applications AI tools never see (upstream `AiToolAccess.IsProcessExcluded`, `AiToolCapture.RedactExcludedWindows`):
/// their windows get no id, can't be captured and are blacked out in what an AI tool's recipe takes from the screen.
public enum AIToolExclusion {
    /// Case, white space and ".app" / ".exe" don't matter ("Proton Pass" = "ProtonPass", "KeePass.exe" = "keepass").
    public static func normalize(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in [".app", ".exe"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        return text.filter { !$0.isWhitespace }
    }

    /// True when one of the names of an app (its name, executable name, bundle identifier) is in the list (security
    /// review SM-L3). A name matches an entry it starts with ("1Password 7", "1Password Helper" for "1Password"); an
    /// entry with a dot is a bundle identifier prefix ("com.agilebits" for "com.agilebits.onepassword7"); a bundle
    /// identifier also matches by its last part ("com.1password.1password" for "1Password").
    public static func isExcluded(names: [String?], excluded: [String]) -> Bool {
        let list = excluded.map(normalize).filter { !$0.isEmpty }
        guard !list.isEmpty else { return false }
        let bundlePrefixes = list.filter { $0.contains(".") }
        let appNames = list.filter { !$0.contains(".") }
        for name in names.compactMap({ $0 }) where !name.isEmpty {
            let normalized = normalize(name)
            if appNames.contains(where: { normalized.hasPrefix($0) }) { return true }
            guard name.contains(".") else { continue }
            if bundlePrefixes.contains(where: { normalized == $0 || normalized.hasPrefix($0 + ".") }) { return true }
            if let last = name.split(separator: ".").last, appNames.contains(where: { normalize(String(last)).hasPrefix($0) }) { return true }
        }
        return false
    }

    /// A black picture of this size: what an AI tool gets when the excluded windows can't be blacked out (fail closed).
    public static func blackImage(width: Int, height: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let size = (max(1, width), max(1, height))
        let context = CGContext(data: nil, width: size.0, height: size.1, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            ?? CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        guard let context else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage()
    }

    /// The parts of a picture to black out: the frames of the excluded windows (Quartz global points) within the picture
    /// whose top left is `origin`, in pixels (top-left origin) at `scale` pixels per point.
    public static func redactionRects(windowFrames: [CGRect], origin: CGPoint, scale: CGFloat, pixelWidth: Int, pixelHeight: Int) -> [CGRect] {
        let pointWidth = CGFloat(pixelWidth) / scale
        let pointHeight = CGFloat(pixelHeight) / scale
        let picture = CGRect(origin: origin, size: CGSize(width: pointWidth, height: pointHeight))
        return windowFrames.compactMap { frame -> CGRect? in
            let overlap = frame.intersection(picture)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return nil }
            let x = (overlap.minX - origin.x) * scale
            let y = (overlap.minY - origin.y) * scale
            return CGRect(x: x, y: y, width: overlap.width * scale, height: overlap.height * scale).integral
        }
    }

    /// The picture with `rects` (pixels, top-left origin) filled black; nil when it can't be drawn.
    public static func blackOut(_ image: CGImage, rects: [CGRect]) -> CGImage? {
        guard !rects.isEmpty else { return image }
        let width = image.width
        let height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: info) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: full)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let pixelHeight = CGFloat(height)
        for rect in rects {
            // CGContext's origin is bottom left
            context.fill(CGRect(x: rect.minX, y: pixelHeight - rect.maxY, width: rect.width, height: rect.height))
        }
        return context.makeImage()
    }
}

/// The picture an AI tool gets back (upstream `AiToolCapture.EncodePng`, `AiToolIpcHandler.CollectResultAsync`): scaled
/// so its longest side is at most the trigger's `MaxImageSize` (default 1568, 0 keeps the size), as PNG.
public enum AIToolImage {
    /// Upstream `AiToolIpcHandler.DefaultMaxImageSize`: larger images cost the AI more and are scaled down by the model.
    public static let defaultMaxImageSize = 1568

    /// The size after scaling; the same size when it fits or `maxSize` is 0.
    public static func scaledSize(width: Int, height: Int, maxSize: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard maxSize > 0, longest > maxSize else { return (width, height) }
        let factor = Double(maxSize) / Double(longest)
        let scaledWidth = max(1, Int((Double(width) * factor).rounded()))
        let scaledHeight = max(1, Int((Double(height) * factor).rounded()))
        return (scaledWidth, scaledHeight)
    }

    /// The PNG of `image` scaled for `maxSize`, with its size; nil when it can't be encoded.
    public static func encodePNG(_ image: CGImage, maxSize: Int) -> (data: Data, width: Int, height: Int)? {
        let size = scaledSize(width: image.width, height: image.height, maxSize: maxSize)
        var output = image
        if size.width != image.width || size.height != image.height {
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            guard let scaled = context.makeImage() else { return nil }
            output = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, size.width, size.height)
    }

    /// The OCR lines for the AI tool: text and bounds in pixels of the unscaled picture (upstream `ocr_lines`).
    public static func ocrLines(_ lines: [RecognizedLine]) -> JSONValue {
        .array(lines.map { line in
            let bounds = line.bounds
            let object: JSONObject = ["text": .string(line.text), "x": .number(Double(bounds.minX)), "y": .number(Double(bounds.minY)),
                                      "width": .number(Double(bounds.width)), "height": .number(Double(bounds.height))]
            return .object(object)
        })
    }
}

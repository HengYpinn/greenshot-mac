// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The pictures of the Annotation step's cursor presets (docs/capture-recipes.md §4 "Standard Windows Cursor Presets"):
/// upstream's Windows cursor names as the Mac's cursors, at 1 pixel per point. The Mac has no public cursor for some
/// (AppStarting, Help, Wait: the arrow; the diagonal sizes: the cross; SizeAll: the open hand).
struct RecipeCursorImages: RecipeCursorImageProviding {
    func cursorImage(named preset: String) async -> (image: CGImage, hotSpot: CGPoint)? {
        await MainActor.run { Self.picture(preset) }
    }

    @MainActor
    static func cursor(named preset: String) -> NSCursor? {
        switch preset.trimmingCharacters(in: .whitespaces).lowercased() {
        case "arrow", "appstarting", "help", "wait": return .arrow
        case "cross", "sizenesw", "sizenwse": return .crosshair
        case "hand": return .pointingHand
        case "ibeam": return .iBeam
        case "no": return .operationNotAllowed
        case "sizeall": return .openHand
        case "sizens": return .resizeUpDown
        case "sizewe": return .resizeLeftRight
        case "uparrow": return .resizeUp
        default: return nil
        }
    }

    @MainActor
    static func picture(_ preset: String) -> (image: CGImage, hotSpot: CGPoint)? {
        guard let cursor = cursor(named: preset) else {
            log.warn("There is no cursor preset '\(preset)'.")
            return nil
        }
        let image = cursor.image
        let width = max(Int(image.size.width.rounded()), 1)
        let height = max(Int(image.size.height.rounded()), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = previous
        guard let picture = bitmap.makeImage() else { return nil }
        return (picture, cursor.hotSpot)
    }
}

/// The clipboard of Core's BarcodeScan step (`CopyToClipboard`): a recorded write of the app.
struct RecipePasteboardWriter: RecipeClipboardWriting {
    func copy(text: String) async {
        await MainActor.run { RecipePasteboard.write(text: text) }
    }
}

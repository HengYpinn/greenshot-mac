// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UniformTypeIdentifiers

/// What the Clipboard trigger (RCP-065, upstream `ClipboardTrigger`) makes of a clipboard change, from the pasteboard's
/// types alone: reading them needs no permission and doesn't show macOS's paste alert, reading the content may.
public struct RecipeClipboardChange: Sendable, Equatable {
    /// The pasteboard types (UTIs) of the first item, in their order.
    public var types: [String]

    public init(types: [String]) {
        self.types = types
    }

    /// The format names for `Clipboard.Formats` and `FormatFilter`: upstream's names where there is one ("PNG",
    /// "HTML Format", "FileDrop", "Text"), the UTI otherwise; each once, in the order of the types.
    public var formats: [String] {
        var result: [String] = []
        for type in types {
            let name = Self.formatNames[type.lowercased()] ?? type
            if !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { result.append(name) }
        }
        return result
    }

    /// Nil when a trigger may look at it; else why not: a password manager's or a transient copy
    /// (nspasteboard.org's `ConcealedType`, `TransientType`), or Greenshot's own copy of editor elements.
    public var ignoredReason: String? {
        let lower = Set(types.map { $0.lowercased() })
        if lower.contains(Self.concealedType) { return "concealed content (a password manager)" }
        if lower.contains(Self.transientType) { return "transient content" }
        if lower.contains(ElementTransfer.pasteboardType.lowercased()) { return "Greenshot's own copy of editor elements" }
        return nil
    }

    /// An image format is on the clipboard (PNG, TIFF, JPEG, any image UTI).
    public var hasImageType: Bool {
        types.contains { type in
            if Self.imageNames.contains(Self.formatNames[type.lowercased()] ?? "") { return true }
            return UTType(type)?.conforms(to: .image) ?? false
        }
    }

    /// Files or HTML: an image only when they contain one (upstream `ContainsImageAsync` reads them), which the app
    /// checks by reading them, only when no image type is there.
    public var mayContainImage: Bool {
        types.contains { type in
            let name = Self.formatNames[type.lowercased()]
            return name == "FileDrop" || name == "HTML Format"
        }
    }

    /// Upstream `FormatFilter`: a comma separated list; a format matches when its name contains an entry (any case).
    /// Windows' bitmap names (Bitmap, DIB, DeviceIndependentBitmap, CF_DIBV5, Format17) mean the Mac's bitmap, TIFF.
    /// No filter: every change matches.
    public func matches(formatFilter: String?) -> Bool {
        let entries = (formatFilter ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !entries.isEmpty else { return true }
        var names = formats
        names.append(contentsOf: types)
        let terms = entries.flatMap { entry -> [String] in
            Self.bitmapAliases.contains(entry.lowercased()) ? [entry, "TIFF"] : [entry]
        }
        return names.contains { name in terms.contains { name.range(of: $0, options: .caseInsensitive) != nil } }
    }

    /// Whether a Clipboard trigger fires (upstream `OnClipboardUpdateReceivedAsync`): with `OnImageCopied` only for an
    /// image (`containsImage` is `hasImageType`, or what the app found in files/HTML), then the format filter.
    public static func fires(onImageCopied: Bool, formatFilter: String?, change: RecipeClipboardChange, containsImage: Bool) -> Bool {
        if onImageCopied, !containsImage { return false }
        return change.matches(formatFilter: formatFilter)
    }

    /// The trigger's variables (upstream `Clipboard.Formats`, `Clipboard.Format`).
    public var variables: [String: JSONValue] {
        let names = formats
        return ["Clipboard.Formats": .array(names.map { .string($0) }), "Clipboard.Format": .string(names.first ?? "Unknown")]
    }

    static let concealedType = "org.nspasteboard.concealedtype"
    static let transientType = "org.nspasteboard.transienttype"
    static let imageNames: Set<String> = ["PNG", "TIFF", "JPEG", "GIF", "BMP", "HEIC", "WEBP"]
    static let bitmapAliases: Set<String> = ["bitmap", "dib", "deviceindependentbitmap", "cf_dib", "cf_dibv5", "cf_bitmap", "format17"]
    /// Lower-cased UTIs (and the old pasteboard names) to upstream's names.
    static let formatNames: [String: String] = [
        "public.png": "PNG", "public.tiff": "TIFF", "next tiff v4.0 pasteboard type": "TIFF", "public.jpeg": "JPEG",
        "com.compuserve.gif": "GIF", "com.microsoft.bmp": "BMP", "public.heic": "HEIC", "org.webmproject.webp": "WEBP",
        "com.adobe.pdf": "PDF", "public.html": "HTML Format", "apple html pasteboard type": "HTML Format",
        "public.file-url": "FileDrop", "nsfilenamespboardtype": "FileDrop", "public.utf8-plain-text": "Text",
        "nsstringpboardtype": "Text", "public.rtf": "Rich Text Format"
    ]
}

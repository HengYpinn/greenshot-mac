// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A destination's key equivalent: ⌘ plus `key`, with ⇧ and ⌥ when set (upstream `DestinationDescriptor.Shortcut`,
/// "Ctrl+Shift+C", with the Mac's File menu keys).
public struct DestinationShortcut: Equatable, Sendable {
    public var key: String
    public var shift: Bool
    public var option: Bool

    public init(_ key: String, shift: Bool = false, option: Bool = false) {
        self.key = key
        self.shift = shift
        self.option = option
    }

    /// e.g. "⇧⌘C".
    public var displayString: String {
        (option ? "⌥" : "") + (shift ? "⇧" : "") + "⌘" + key.uppercased()
    }
}

/// How the destinations show in the picker: upstream `DestinationDescriptor` (name, priority, icon, shortcut) of each
/// destination, with SF Symbols for upstream's icons.
extension CaptureDestination {
    /// The picker's name of the destination.
    public var pickerTitle: String {
        switch self {
        case .picker: return "Ask Every Time"
        case .editor: return "Open in Image Editor"
        case .clipboard: return "Copy to Clipboard"
        case .file: return "Save Directly"
        case .fileAs: return "Save As…"
        case .printer: return "Print…"
        case .email: return "Email…"
        case .share: return "Share…"
        case .ocr: return "Copy Text (OCR)"
        case .externalCommand: return "External Command"
        case .pdf: return "Save as PDF…"
        case .openWith: return "Open With"
        case .qrCode: return "QR Code"
        case .jira: return "Upload to Jira…"
        case .confluence: return "Upload to Confluence…"
        case .box: return "Upload to Box"
        case .dropbox: return "Upload to Dropbox"
        }
    }

    /// Upstream `DestinationDescriptor.Priority`, lower first: the file destinations 0, the editor 1, clipboard and
    /// printer 2, mail, share and OCR 3, QR codes and the Office applications (here "Open With") 4, the plugins 10.
    public var pickerPriority: Int {
        switch self {
        case .file, .fileAs, .pdf: return 0
        case .picker, .editor: return 1
        case .clipboard, .printer: return 2
        case .email, .share, .ocr: return 3
        case .qrCode, .openWith: return 4
        case .externalCommand, .jira, .confluence, .box, .dropbox: return 10
        }
    }

    /// The SF Symbol for upstream's icon of the destination.
    public var symbolName: String {
        switch self {
        case .picker: return "list.bullet"
        case .editor: return "pencil.and.outline"
        case .clipboard: return "doc.on.clipboard"
        case .file: return "square.and.arrow.down"
        case .fileAs: return "square.and.arrow.down.on.square"
        case .printer: return "printer"
        case .email: return "envelope"
        case .share: return "square.and.arrow.up"
        case .ocr: return "text.viewfinder"
        case .externalCommand: return "terminal"
        case .pdf: return "doc.richtext"
        case .openWith: return "arrow.up.forward.app"
        case .qrCode: return "qrcode"
        case .jira: return "checklist"
        case .confluence: return "doc.text"
        case .box: return "shippingbox"
        case .dropbox: return "icloud.and.arrow.up"
        }
    }

    /// The key of the File menu entry (upstream: Ctrl+S, Ctrl+Shift+S, Ctrl+Shift+C, Ctrl+P, Ctrl+E). The File menu's
    /// Save (⌘S) saves a new capture directly, so "Save directly" has ⌘S like upstream.
    public var shortcut: DestinationShortcut? {
        switch self {
        case .file: return DestinationShortcut("s")
        case .fileAs: return DestinationShortcut("s", shift: true)
        case .pdf: return DestinationShortcut("p", option: true)
        case .clipboard: return DestinationShortcut("c", shift: true)
        case .printer: return DestinationShortcut("p")
        case .ocr: return DestinationShortcut("t", option: true)
        case .email: return DestinationShortcut("e")
        default: return nil
        }
    }
}

/// The order of the picker (upstream `DestinationComparer`): by priority, then by name, compared character by character.
public enum DestinationOrder {
    public static func precedes(_ a: (priority: Int, title: String), _ b: (priority: Int, title: String)) -> Bool {
        if a.priority != b.priority { return a.priority < b.priority }
        return a.title.unicodeScalars.lexicographicallyPrecedes(b.title.unicodeScalars)
    }

    public static func sorted<T>(_ items: [T], by key: (T) -> (priority: Int, title: String)) -> [T] {
        // Stable: equal entries keep their order.
        items.enumerated().sorted { x, y in
            let a = key(x.element), b = key(y.element)
            if precedes(a, b) { return true }
            if precedes(b, a) { return false }
            return x.offset < y.offset
        }.map(\.element)
    }
}

/// Which destinations the picker offers (upstream `IDestination.IsAvailableFor`).
public enum DestinationAvailability {
    /// The uploads only once they are set up (upstream: Jira and Confluence with a URL; Box and Dropbox need the
    /// user's own app key here). "Ask every time" is the picker itself.
    public static func isSetUp(_ destination: CaptureDestination, in settings: AppSettings) -> Bool {
        func filled(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch destination {
        case .picker: return false
        case .jira: return filled(settings.jira.url)
        case .confluence: return filled(settings.confluence.url)
        case .box: return filled(settings.box.clientID)
        case .dropbox: return filled(settings.dropbox.appKey)
        default: return true
        }
    }
}

extension FilenamePattern {
    /// A title cut to `length` characters for a menu entry (upstream shows the first 20 characters of an editor's title).
    public static func menuTitle(_ title: String, length: Int = 20) -> String {
        let line = title.replacingOccurrences(of: "\n", with: " ")
        return line.count > length ? String(line.prefix(length)) + "…" : line
    }
}

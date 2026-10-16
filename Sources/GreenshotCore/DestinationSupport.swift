// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How important a message after a capture is, for the `notificationLevel` setting (upstream `NotificationKind`).
public enum MessageKind: Sendable {
    case info, warning, error
}

extension NotificationLevel {
    /// Whether a message of `kind` is shown at this level (upstream `NotificationLevel` in `ICoreConfiguration.cs`).
    public func shows(_ kind: MessageKind) -> Bool {
        switch self {
        case .all: return true
        case .warnings: return kind != .info
        case .errors: return kind == .error
        case .none: return false
        }
    }
}

/// Helpers the destinations share.
public enum DestinationSupport {
    /// `url`, or with " (2)", " (3)", … before the extension when a file is there already (upstream with
    /// `OutputFileAllowOverwrite` off).
    public static func uniqueURL(for url: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = "\(base) (\(number))"
            let candidate = ext.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(ext)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// The HTML clipboard format: the PNG embedded in an `<img>` (upstream `ClipboardHelper` "HTML DATAURL").
    public static func htmlSnippet(png: Data, width: Int, height: Int) -> String {
        "<img src=\"data:image/png;base64,\(png.base64EncodedString())\" width=\"\(width)\" height=\"\(height)\">"
    }

    /// Splits a recipient list ("a@b.c, d@e.f; g@h.i") into addresses.
    public static func recipients(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A `mailto:` URL with recipients and subject (no attachment: mailto can't carry one).
    public static func mailtoURL(to: [String], cc: [String], bcc: [String], subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to.joined(separator: ",")
        var query: [URLQueryItem] = []
        if !cc.isEmpty { query.append(URLQueryItem(name: "cc", value: cc.joined(separator: ","))) }
        if !bcc.isEmpty { query.append(URLQueryItem(name: "bcc", value: bcc.joined(separator: ","))) }
        if !subject.isEmpty { query.append(URLQueryItem(name: "subject", value: subject)) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }
}

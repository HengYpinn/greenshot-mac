// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The messages of the browser extension (Extensions/Browser/background.js) and the app's replies (upstream
/// `Ipc/BrowserExtension/BrowserExtensionIpcExtension.cs`). The extension's members that aren't envelope members
/// (`metadata`, `data`, `url`, `title`, `browser`, `extension_version`) arrive in `IPCEnvelope.extra`.
public enum BrowserCommand {
    public static let handshake = "HANDSHAKE"
    public static let importCapture = "IMPORT_CAPTURE"
    public static let tabChanged = "TAB_CHANGED"
    /// The three, all for the `native_messaging` source only.
    public static let all = [handshake, importCapture, tabChanged]
}

/// IMPORT_CAPTURE: `{"metadata": {"title", "url", "timestamp", "tab_width"}, "data": {"mime_type", "encoding",
/// "payload"}, "browser"}`. `tab_width` (the tab's width in CSS pixels) and `browser` are the Mac extension's additions.
public struct BrowserImportRequest: Equatable, Sendable {
    /// The tab's title; upstream's fallback "Browser Capture".
    public var title: String
    public var url: String
    public var browser: String?
    public var tabWidth: Double?
    /// The image, base64.
    public var payload: String?

    public init(envelope: IPCEnvelope, origin: String? = nil) {
        let metadata = envelope.extra["metadata"]?.objectValue
        let title = BrowserText.clean(metadata?["title"]?.stringValue ?? "", limit: BrowserText.titleLimit)
        self.title = title.isEmpty ? "Browser Capture" : title
        url = BrowserText.clean(metadata?["url"]?.stringValue ?? "", limit: BrowserText.urlLimit)
        browser = BrowserText.browserName(envelope.extra["browser"]?.stringValue, origin: origin)
        if let width = metadata?["tab_width"]?.doubleValue, width.isFinite, width > 0 { tabWidth = width }
        payload = envelope.extra["data"]?.objectValue?["payload"]?.stringValue
    }

    /// Pixels per point of the capture: the image's width over the tab's CSS width (2 on a Retina display), whole,
    /// between 1 and 4; 1 when the extension didn't say.
    public func scale(pixelWidth: Int) -> CGFloat {
        guard let tabWidth, pixelWidth > 0 else { return 1 }
        let ratio = (Double(pixelWidth) / tabWidth).rounded()
        return CGFloat(min(4, max(1, ratio)))
    }

    /// The metadata a file name pattern reads as `${url}` and `${browser}` (upstream `CaptureDetails.AddMetaData`).
    public var metadata: [String: String] {
        var values: [String: String] = [:]
        if !url.isEmpty { values["url"] = url }
        if let browser { values["browser"] = browser }
        return values
    }
}

/// TAB_CHANGED: `{"url", "title", "browser"}`.
public struct BrowserTabChange: Equatable, Sendable {
    public var url: String
    public var title: String

    public init(envelope: IPCEnvelope) {
        url = envelope.extra["url"]?.stringValue ?? ""
        title = envelope.extra["title"]?.stringValue ?? ""
    }
}

/// The app's replies to the extension.
public enum BrowserReplies {
    /// Upstream's `full_page_delay_ms`.
    public static let fullPageDelayMilliseconds = 250

    /// HANDSHAKE: Greenshot is ready (upstream `HandleHandshakeAsync`). Upstream also sends `capture_format: "png"` and
    /// `track_tab_urls: true`, which the extension merges over its stored options, so every reconnect would undo what
    /// the user chose on the extension's options page; the Mac leaves the options to the extension.
    public static func handshake(version: String) -> IPCReply {
        IPCReply(status: "ready", exitCode: IPCExitCode.ok,
                 extra: ["greenshot_running": .bool(true), "greenshot_version": .string(version),
                         "config": .object(["full_page_delay_ms": .number(Double(fullPageDelayMilliseconds))])])
    }

    /// IMPORT_CAPTURE accepted: `{"status": "ok", "reply_to": "IMPORT_CAPTURE", "exit_code": 0, "width", "height"}`.
    public static func importAccepted(width: Int, height: Int) -> IPCReply {
        .ok(extra: ["reply_to": .string(BrowserCommand.importCapture), "width": .number(Double(width)),
                    "height": .number(Double(height))])
    }

    /// IMPORT_CAPTURE refused: `{"status": "error", "reply_to": "IMPORT_CAPTURE", "exit_code": 1, "stderr": "Error: ...."}`.
    public static func importRejected(_ reason: String) -> IPCReply {
        IPCReply(status: "error", exitCode: IPCExitCode.failure, stderr: "Error: \(reason).",
                 extra: ["reply_to": .string(BrowserCommand.importCapture)])
    }
}

/// Cleaning of the extension's texts (upstream `BrowserContextTracker.Sanitize`).
public enum BrowserText {
    /// Upstream's limits for the URL and the title.
    public static let urlLimit = 2048
    public static let titleLimit = 512

    /// The text without control characters (upstream `char.IsControl`: category Cc only, so emoji sequences with a
    /// zero-width joiner stay), at most `limit` characters; "" for blank text.
    public static func clean(_ text: String, limit: Int) -> String {
        var result = ""
        var count = 0
        for character in text where !character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            guard count < limit else { break }
            result.append(character)
            count += 1
        }
        return result.allSatisfy(\.isWhitespace) ? "" : result
    }

    /// The browser the extension runs in, as its `getBrowserName()` says ("chrome", "edge", "firefox"); nil for anything
    /// that isn't a short lower-case ASCII name. Without one, a Firefox add-on id as the origin means "firefox" (a
    /// `chrome-extension://` origin can be Chrome, Edge, Brave, ...).
    public static func browserName(_ claimed: String?, origin: String?) -> String? {
        if let claimed {
            let name = claimed.trimmingCharacters(in: .whitespaces).lowercased()
            let allowed = name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
            if !name.isEmpty, name.count <= 32, allowed { return name }
        }
        if let origin, !origin.isEmpty, !origin.lowercased().hasPrefix("chrome-extension://") { return "firefox" }
        return nil
    }
}

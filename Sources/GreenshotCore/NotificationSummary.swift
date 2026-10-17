// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A barcode found in a capture, for a row of the notification (upstream `IBarcodeFeature`).
public struct NotificationBarcode: Equatable, Sendable {
    /// What the code says.
    public var text: String
    /// A QR code ("QR code: …"); other kinds are "Barcode: …".
    public var isQRCode: Bool

    public init(text: String, isQRCode: Bool) {
        self.text = text
        self.isQRCode = isQRCode
    }

    /// A barcode the Vision framework found (`DetectedBarcode.symbology` is "QR" for a QR code).
    public init(_ detected: DetectedBarcode) {
        self.init(text: detected.payload, isQRCode: detected.symbology.caseInsensitiveCompare("QR") == .orderedSame)
    }
}

/// A link the notification can copy: the text that names it in a choice ("Box: https://…") and the link itself
/// (upstream `NotificationChoice`).
public struct NotificationLink: Equatable, Sendable {
    public var text: String
    public var value: String

    public init(text: String, value: String) {
        self.text = text
        self.value = value
    }
}

/// The buttons of a notification after a capture (upstream `NotificationButtons`, same action names).
public enum NotificationAction: String, CaseIterable, Sendable {
    /// Opens the kept capture in the editor.
    case edit = "edit"
    /// Shows the saved file in Finder.
    case showInFolder = "show-in-folder"
    /// Copies the link of an upload or of a QR code; with several links the user chooses one.
    case copyLink = "copy-link"

    public var title: String {
        switch self {
        case .edit: return "Edit"
        case .showInFolder: return "Show in Finder"
        case .copyLink: return "Copy Link"
        }
    }

    private var letter: String {
        switch self {
        case .edit: return "E"
        case .showInFolder: return "F"
        case .copyLink: return "L"
        }
    }

    /// The category of a notification with these buttons, e.g. "capture.EF"; nil without buttons. macOS needs every
    /// category registered before a notification uses it, see `allCombinations`.
    public static func categoryIdentifier(for actions: [NotificationAction]) -> String? {
        guard !actions.isEmpty else { return nil }
        return "capture." + allCases.filter(actions.contains).map(\.letter).joined()
    }

    /// Every combination of buttons a notification can have, in button order (7 of them).
    public static var allCombinations: [[NotificationAction]] {
        (1..<(1 << allCases.count)).map { mask in
            allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
        }
    }
}

/// One notification after a capture: what upstream's Notification step shows for the exports of a flow
/// (`Greenshot/Recipes/Pipeline/ExportNotification.cs` `CreateNotification`).
public struct NotificationSummaryContent: Equatable, Sendable {
    /// An error when an export failed (for the notification level and the icon), else info.
    public var kind: MessageKind
    /// What was captured (the window title), else "Greenshot".
    public var title: String
    /// One line per export, then one per barcode.
    public var lines: [String]
    /// The kept capture a click offers again (a UUID); nil when none is kept.
    public var captureId: String?
    /// The file the capture was saved to (the last one): Show in Finder.
    public var savedFile: URL?
    /// The links of the uploads, then those of the QR codes: Copy Link. Only http and https, each once.
    public var links: [NotificationLink]
    /// What a click opens when there are no buttons and no kept capture (the in-app message, like upstream's balloon):
    /// the upload link or the saved file of the last export.
    public var opens: URL?
    /// Whether an export is behind the notification (not only barcodes): only then a capture is kept.
    public var hasExports: Bool

    public var body: String { lines.joined(separator: "\n") }

    /// The buttons (upstream `NotificationButtons.Create`).
    public var actions: [NotificationAction] {
        var actions: [NotificationAction] = []
        if captureId != nil { actions.append(.edit) }
        if savedFile != nil { actions.append(.showInFolder) }
        if !links.isEmpty { actions.append(.copyLink) }
        return actions
    }

    public var categoryIdentifier: String? { NotificationAction.categoryIdentifier(for: actions) }

    public init(kind: MessageKind, title: String, lines: [String], captureId: String? = nil, savedFile: URL? = nil,
                links: [NotificationLink] = [], opens: URL? = nil, hasExports: Bool = true) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.captureId = captureId
        self.savedFile = savedFile
        self.links = links
        self.opens = opens
        self.hasExports = hasExports
    }
}

/// Builds the notification after a capture from how its exports ended: port of upstream `ExportNotification`.
public enum NotificationSummary {
    /// Upstream `MaxBarcodes`.
    public static let maxBarcodes = 3
    /// Upstream `MaxBarcodeText`.
    public static let maxBarcodeText = 120
    /// The title when the capture has none (upstream "Greenshot").
    public static let defaultTitle = "Greenshot"

    /// The exports a notification shows: those with something to say, none when the settings don't show their kind
    /// (upstream `GetShownExports`). `exportedBy` names the destination; `fallbackName` when it is missing.
    public static func shownExports(_ exports: [ExportResult], settings: AppSettings,
                                    fallbackName: String = defaultTitle) -> [ExportResult] {
        let shown = exports.filter { message(for: $0, fallbackName: fallbackName) != nil }
        guard !shown.isEmpty, settings.showNotifications, settings.notificationLevel.shows(kind(of: shown)) else { return [] }
        return shown
    }

    /// Error when an export failed, else info (upstream `GetKind`).
    public static func kind(of exports: [ExportResult]) -> MessageKind {
        exports.contains { $0.status == .failed } ? .error : .info
    }

    /// The line of an export: the text of the editor's status bar (upstream `ExportResultHandler.GetMessage`), with a
    /// warning sign when it failed. Nil for nothing to say (declined, or failed without a reason).
    public static func message(for export: ExportResult, fallbackName: String = defaultTitle) -> String? {
        guard let message = EditorWindowStatus.message(for: export, destination: export.exportedBy ?? fallbackName) else { return nil }
        return message.isError ? "⚠ " + message.text : message.text
    }

    /// The notification for the exports of a capture and the barcodes found in it; nil when nothing is shown (no
    /// exports with something to say and no barcodes, or the settings hide it). `captureId` is filled in by the caller
    /// once it decided to keep the capture.
    public static func make(title: String, exports: [ExportResult], barcodes: [NotificationBarcode] = [],
                            settings: AppSettings) -> NotificationSummaryContent? {
        let shown = shownExports(exports, settings: settings)
        let codes = uniqueBarcodes(barcodes)
        if shown.isEmpty && (codes.isEmpty || !settings.showNotifications || !settings.notificationLevel.shows(.info)) {
            return nil
        }
        var lines = shown.compactMap { message(for: $0) }
        // The links of the exports, each with its destination, then those of the barcodes: copied only, never opened.
        var links = shown.compactMap { export -> NotificationLink? in
            guard export.isSucceeded, let link = export.link else { return nil }
            return NotificationLink(text: "\(export.exportedBy ?? defaultTitle): \(link.absoluteString)", value: link.absoluteString)
        }
        for code in codes {
            let display = barcodeDisplay(code.text)
            let text = (code.isQRCode ? "QR code: " : "Barcode: ") + display.text
            lines.append(text)
            if let link = display.link {
                // What is copied is what is shown, with the host in punycode.
                links.append(NotificationLink(text: text, value: link))
            }
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationSummaryContent(kind: kind(of: shown), title: trimmedTitle.isEmpty ? defaultTitle : trimmedTitle,
                                          lines: lines, savedFile: savedFile(of: shown), links: webLinks(links),
                                          opens: opens(of: shown), hasExports: !shown.isEmpty)
    }

    /// The file the capture was saved to: the last export with a file that counts as saved. Mail, Open With and the
    /// external commands report a temporary file (`clearsModified` false), which Show in Finder must not offer.
    public static func savedFile(of exports: [ExportResult]) -> URL? {
        exports.last { $0.isSucceeded && $0.link == nil && $0.fileURL != nil && $0.clearsModified }?.fileURL
    }

    /// What a click on the in-app message opens: the link or saved file of the last export that has one (upstream
    /// `ExportNotification.Open`).
    public static func opens(of exports: [ExportResult]) -> URL? {
        guard let last = exports.last(where: { $0.isSucceeded && ($0.link != nil || ($0.fileURL != nil && $0.clearsModified)) }) else {
            return nil
        }
        return last.link ?? last.fileURL
    }

    /// The links that can be copied: http and https only, each value once, in order.
    public static func webLinks(_ links: [NotificationLink]) -> [NotificationLink] {
        var seen = Set<String>()
        return links.filter { isWebLink($0.value) && seen.insert($0.value).inserted }
    }

    /// Only http and https are links: no file:, javascript: or the scheme of an app (upstream `IsWebLink`).
    public static func isWebLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty else { return false }
        return true
    }

    /// The barcodes to show: not empty, each text once, at most `maxBarcodes` (upstream `GetBarcodes`).
    public static func uniqueBarcodes(_ barcodes: [NotificationBarcode]) -> [NotificationBarcode] {
        var seen = Set<String>()
        let unique = barcodes.filter { code in
            !code.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert(code.text).inserted
        }
        return Array(unique.prefix(maxBarcodes))
    }

    /// What a barcode shows (upstream `GetBarcodeDisplayText`). A barcode is someone else's content: an http(s) link is
    /// shown completely with its host as the DNS sees it (punycode, so a look-alike letter of another alphabet shows as
    /// `xn--…`) and without user info, and `link` is that text; anything else is shortened and is no link.
    public static func barcodeDisplay(_ barcode: String) -> (text: String, link: String?) {
        if let link = displayedLink(barcode.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return (link, link)
        }
        let text = barcode.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard text.count > maxBarcodeText else { return (text, nil) }
        return (String(text.prefix(maxBarcodeText)) + "…", nil)
    }

    /// `scheme://host[:port]/path?query#fragment` of an http(s) link, the host in punycode and lower case; nil for
    /// anything else.
    static func displayedLink(_ text: String) -> String? {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.encodedHost?.lowercased(), !host.isEmpty else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = components.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? ""
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        let fragment = components.percentEncodedFragment.map { "#" + $0 } ?? ""
        return "\(scheme)://\(host)\(port)\(path)\(query)\(fragment)"
    }
}

/// What a notification after a capture carries for its click and buttons, as the `userInfo` of a macOS notification.
/// The click can come after a restart, so the notification carries what its buttons act on; whatever comes back is
/// checked before it is used (upstream `ToastArguments` and `NotificationButtons.Run`).
public struct NotificationPayload: Equatable, Sendable {
    public var captureId: String?
    /// The path of the saved file.
    public var savedFile: String?
    public var links: [NotificationLink]
    /// The capture's title and date, for the editor and the destination picker.
    public var title: String?
    public var date: Date?

    public init(captureId: String? = nil, savedFile: String? = nil, links: [NotificationLink] = [], title: String? = nil,
                date: Date? = nil) {
        self.captureId = captureId
        self.savedFile = savedFile
        self.links = links
        self.title = title
        self.date = date
    }

    private enum Key {
        static let captureId = "captureId"
        static let savedFile = "savedFile"
        static let links = "links"
        static let title = "title"
        static let date = "date"
    }

    /// Plist types only (strings, numbers, arrays), as `UNNotificationContent.userInfo` needs them.
    public var userInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let captureId { info[Key.captureId] = captureId }
        if let savedFile { info[Key.savedFile] = savedFile }
        if !links.isEmpty { info[Key.links] = links.map { [$0.text, $0.value] } }
        if let title { info[Key.title] = title }
        if let date { info[Key.date] = date.timeIntervalSince1970 }
        return info
    }

    /// Reads a `userInfo` back; values of the wrong type are left out.
    public init(userInfo: [AnyHashable: Any]) {
        captureId = userInfo[Key.captureId] as? String
        savedFile = userInfo[Key.savedFile] as? String
        links = ((userInfo[Key.links] as? [Any]) ?? []).compactMap { entry in
            guard let pair = entry as? [Any], pair.count == 2, let text = pair[0] as? String, let value = pair[1] as? String else { return nil }
            return NotificationLink(text: text, value: value)
        }
        title = userInfo[Key.title] as? String
        date = (userInfo[Key.date] as? Double).map(Date.init(timeIntervalSince1970:))
    }

    /// The saved file to show in Finder, when it is still there.
    public func existingSavedFile(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        guard let savedFile, savedFile.hasPrefix("/"), exists(savedFile) else { return nil }
        return URL(fileURLWithPath: savedFile)
    }

    /// The links that may be copied (http and https).
    public var webLinks: [NotificationLink] { NotificationSummary.webLinks(links) }
}

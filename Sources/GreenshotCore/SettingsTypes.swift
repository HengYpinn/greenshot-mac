// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

// The value types behind the settings that upstream keeps in `ICoreConfiguration.cs`, `IEditorConfiguration.cs`,
// `IPdfConfiguration.cs` and `IExternalCommandConfiguration.cs`. Every type here is flat and Codable, with
// defaults from upstream, so settings written by an older version still load (see `AppSettings.init(from:)`).

// MARK: Capture

/// A size of the fixed-size capture mode (upstream `FixedCaptureSizes`, "640x480" strings).
public struct CaptureSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Parses "640x480" (also "640 x 480", "640X480").
    public init?(_ text: String) {
        let parts = text.lowercased().split(separator: "x").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
        self.init(width: w, height: h)
    }

    public var displayString: String { "\(width)×\(height)" }

    /// Upstream's defaults.
    public static let defaults = [CaptureSize(width: 640, height: 480), CaptureSize(width: 800, height: 600),
                                  CaptureSize(width: 1024, height: 768), CaptureSize(width: 1280, height: 720),
                                  CaptureSize(width: 1920, height: 1080)]
}

/// Which corner of the fixed-size rectangle follows the mouse (upstream `FixedCaptureAnchor`).
public enum FixedCaptureAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft, center

    public var displayName: String {
        switch self {
        case .topLeft: return String(localized: "Top left")
        case .topRight: return String(localized: "Top right")
        case .bottomRight: return String(localized: "Bottom right")
        case .bottomLeft: return String(localized: "Bottom left")
        case .center: return String(localized: "Center", comment: "The centre of the fixed-size capture rectangle follows the mouse")
        }
    }

    /// The next anchor when C is pressed on the capture screen.
    public var next: FixedCaptureAnchor {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// What the full screen hotkey captures (upstream `ScreenCaptureMode`).
public enum ScreenCaptureMode: String, Codable, CaseIterable, Sendable {
    /// The screen the mouse is on.
    case auto
    /// Every screen, joined.
    case fullScreen
    /// The screen with number `screenToCapture` (1-based).
    case fixed

    public var displayName: String {
        switch self {
        case .auto: return String(localized: "The screen with the mouse")
        case .fullScreen: return String(localized: "All screens")
        case .fixed: return String(localized: "One screen")
        }
    }
}

/// Which messages are shown (upstream `NotificationLevel`).
public enum NotificationLevel: String, Codable, CaseIterable, Sendable {
    case all, warnings, errors, none

    public var displayName: String {
        switch self {
        case .all: return String(localized: "notifications.level.all", defaultValue: "All", comment: "Which messages are shown: all of them (Settings › Notifications)")
        case .warnings: return String(localized: "Warnings and errors")
        case .errors: return String(localized: "Errors only")
        case .none: return String(localized: "notifications.level.none", defaultValue: "None", comment: "Which messages are shown: none of them (Settings › Notifications)")
        }
    }
}

// MARK: Effects

/// Upstream `DropShadowEffect`: Darkness 0.6, ShadowSize 7, ShadowOffset (-1, -1).
public struct DropShadowSettings: Codable, Equatable, Sendable {
    /// 0...1, how dark the shadow is.
    public var darkness: Double = 0.6
    /// Blur size in points.
    public var size: Int = 7
    public var offsetX: Int = -1
    public var offsetY: Int = -1

    public init(darkness: Double = 0.6, size: Int = 7, offsetX: Int = -1, offsetY: Int = -1) {
        self.darkness = darkness
        self.size = size
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    enum CodingKeys: String, CodingKey { case darkness, size, offsetX, offsetY }

    /// Every value falls back to its default, so settings written before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DropShadowSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        darkness = value(.darkness, d.darkness)
        size = value(.size, d.size)
        offsetX = value(.offsetX, d.offsetX)
        offsetY = value(.offsetY, d.offsetY)
    }
}

/// Upstream `TornEdgeEffect`: ToothHeight 12, tooth ranges 20, all edges, GenerateShadow true with the drop shadow's
/// defaults (Darkness 0.6, ShadowSize 7, ShadowOffset -1, -1), BackgroundColor transparent.
public struct TornEdgeSettings: Codable, Equatable, Sendable {
    public var toothHeight: Int = 12
    public var horizontalToothRange: Int = 20
    public var verticalToothRange: Int = 20
    public var top = true
    public var left = true
    public var right = true
    public var bottom = true
    public var shadow = true
    /// The shadow's own settings (upstream `TornEdgeSettingsWindow`'s shadow group), like the drop shadow's.
    public var shadowDarkness: Double = 0.6
    public var shadowSize: Int = 7
    public var shadowOffsetX: Int = -1
    public var shadowOffsetY: Int = -1
    /// What the torn off parts (and the room of the shadow) show; transparent by default.
    public var backgroundColor: RGBAColor = .clear

    public init(toothHeight: Int = 12, horizontalToothRange: Int = 20, verticalToothRange: Int = 20,
                top: Bool = true, left: Bool = true, right: Bool = true, bottom: Bool = true, shadow: Bool = true,
                shadowDarkness: Double = 0.6, shadowSize: Int = 7, shadowOffsetX: Int = -1, shadowOffsetY: Int = -1,
                backgroundColor: RGBAColor = .clear) {
        self.toothHeight = toothHeight
        self.horizontalToothRange = horizontalToothRange
        self.verticalToothRange = verticalToothRange
        self.top = top
        self.left = left
        self.right = right
        self.bottom = bottom
        self.shadow = shadow
        self.shadowDarkness = shadowDarkness
        self.shadowSize = shadowSize
        self.shadowOffsetX = shadowOffsetX
        self.shadowOffsetY = shadowOffsetY
        self.backgroundColor = backgroundColor
    }

    /// The shadow as drop shadow settings.
    public var dropShadow: DropShadowSettings {
        DropShadowSettings(darkness: shadowDarkness, size: shadowSize, offsetX: shadowOffsetX, offsetY: shadowOffsetY)
    }

    enum CodingKeys: String, CodingKey {
        case toothHeight, horizontalToothRange, verticalToothRange, top, left, right, bottom, shadow
        case shadowDarkness, shadowSize, shadowOffsetX, shadowOffsetY, backgroundColor
    }

    /// Every value falls back to its default, so settings written before the shadow options still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TornEdgeSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        toothHeight = value(.toothHeight, d.toothHeight)
        horizontalToothRange = value(.horizontalToothRange, d.horizontalToothRange)
        verticalToothRange = value(.verticalToothRange, d.verticalToothRange)
        top = value(.top, d.top)
        left = value(.left, d.left)
        right = value(.right, d.right)
        bottom = value(.bottom, d.bottom)
        shadow = value(.shadow, d.shadow)
        shadowDarkness = value(.shadowDarkness, d.shadowDarkness)
        shadowSize = value(.shadowSize, d.shadowSize)
        shadowOffsetX = value(.shadowOffsetX, d.shadowOffsetX)
        shadowOffsetY = value(.shadowOffsetY, d.shadowOffsetY)
        backgroundColor = value(.backgroundColor, d.backgroundColor)
    }
}

/// Upstream `TextObfuscationWindow` options (`TEXT_OBFUSCATION_FEATURE.md`), with the dialog's slider defaults
/// for the effects.
public struct TextObfuscationSettings: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Sendable { case words, lines }
    public enum Effect: String, Codable, CaseIterable, Sendable { case pixelate, blur, highlight, magnify }

    public var searchPattern = ""
    public var useRegex = false
    public var caseSensitive = false
    public var scope: Scope = .words
    public var effect: Effect = .pixelate
    /// Percent of the found box.
    public var paddingHorizontal = 10
    public var paddingVertical = 20
    public var offsetX = 0
    public var offsetY = 0
    /// The block size of the pixelate effect, points (1...50).
    public var pixelSize = 10
    /// The radius of the blur effect, points (1...30).
    public var blurRadius = 10
    /// The factor of the magnify effect (1...10).
    public var magnification = 2
    /// The color of the highlight effect.
    public var highlightColor: RGBAColor = .yellow

    public init() {}

    enum CodingKeys: String, CodingKey {
        case searchPattern, useRegex, caseSensitive, scope, effect, paddingHorizontal, paddingVertical, offsetX, offsetY
        case pixelSize, blurRadius, magnification, highlightColor
    }

    /// Every value falls back to its default, so settings written before the effect options still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TextObfuscationSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        searchPattern = value(.searchPattern, d.searchPattern)
        useRegex = value(.useRegex, d.useRegex)
        caseSensitive = value(.caseSensitive, d.caseSensitive)
        scope = value(.scope, d.scope)
        effect = value(.effect, d.effect)
        paddingHorizontal = value(.paddingHorizontal, d.paddingHorizontal)
        paddingVertical = value(.paddingVertical, d.paddingVertical)
        offsetX = value(.offsetX, d.offsetX)
        offsetY = value(.offsetY, d.offsetY)
        pixelSize = value(.pixelSize, d.pixelSize)
        blurRadius = value(.blurRadius, d.blurRadius)
        magnification = value(.magnification, d.magnification)
        highlightColor = value(.highlightColor, d.highlightColor)
    }
}

// MARK: Output

/// The clipboard formats a copy writes (upstream `ClipboardFormats`, default PNG and DIB; TIFF is the Mac's DIB).
public enum ClipboardFormat: String, Codable, CaseIterable, Sendable {
    case png, tiff, jpeg, html

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .jpeg: return "JPEG"
        case .html: return String(localized: "HTML (image embedded)")
        }
    }

    public static let defaults: [ClipboardFormat] = [.png, .tiff]
}

/// Upstream `PrintOptions` and the `OutputPrint*` settings.
public struct PrintSettings: Codable, Equatable, Sendable {
    /// Show the print options dialog before printing.
    public var promptOptions = true
    public var inverted = false
    public var grayscale = false
    public var monochrome = false
    public var monochromeThreshold = 127
    /// Print a footer with the capture time and title.
    public var footer = true
    public var footerPattern = "${capturetime:d\"D\"} ${capturetime:d\"T\"} - ${title}"
    public var allowShrink = true
    public var allowEnlarge = false
    public var allowRotate = false
    public var center = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case promptOptions, inverted, grayscale, monochrome, monochromeThreshold, footer, footerPattern, allowShrink
        case allowEnlarge, allowRotate, center
    }

    /// Every value falls back to its default, so settings written before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrintSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        promptOptions = value(.promptOptions, d.promptOptions)
        inverted = value(.inverted, d.inverted)
        grayscale = value(.grayscale, d.grayscale)
        monochrome = value(.monochrome, d.monochrome)
        monochromeThreshold = value(.monochromeThreshold, d.monochromeThreshold)
        footer = value(.footer, d.footer)
        footerPattern = value(.footerPattern, d.footerPattern)
        allowShrink = value(.allowShrink, d.allowShrink)
        allowEnlarge = value(.allowEnlarge, d.allowEnlarge)
        allowRotate = value(.allowRotate, d.allowRotate)
        center = value(.center, d.center)
    }
}

/// Upstream `MailApiTo/CC/BCC` and the Office plugin's `EmailSubjectPattern`.
public struct EmailSettings: Codable, Equatable, Sendable {
    public var to = ""
    public var cc = ""
    public var bcc = ""
    public var subjectPattern = "${title}"

    public init() {}

    enum CodingKeys: String, CodingKey { case to, cc, bcc, subjectPattern }

    /// Every value falls back to its default, so settings written before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EmailSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        to = value(.to, d.to)
        cc = value(.cc, d.cc)
        bcc = value(.bcc, d.bcc)
        subjectPattern = value(.subjectPattern, d.subjectPattern)
    }
}

/// One command of upstream's External Command plugin: `{0}` in the arguments is the path of a temporary PNG.
public struct ExternalCommand: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    /// The executable, e.g. `/usr/bin/open`.
    public var command: String
    /// Arguments as one line; `{0}` is the image file. Quotes group words.
    public var arguments: String
    public var runInBackground = true
    /// Look for a URL in the output and put it on the clipboard (upstream `ParseOutputForUri` + `UriToClipboard`).
    public var copyURLFromOutput = true
    /// Put the whole output on the clipboard (upstream `OutputToClipboard`).
    public var copyOutputToClipboard = false
    /// The format of the file the command gets (upstream `OutputFormat`, per command); one of `ImageFormat.imageFormats`.
    public var format: ImageFormat = .png
    /// Write the command's output to the log (upstream `ShowStandardOutputInLog`, per command
    /// `ShowStandardOutputInLogCommand`, default off); its errors are always logged as warnings, like upstream.
    public var showOutputInLog = false

    public init(id: UUID = UUID(), name: String, command: String, arguments: String = "\"{0}\"",
                runInBackground: Bool = true, copyURLFromOutput: Bool = true, copyOutputToClipboard: Bool = false,
                format: ImageFormat = .png, showOutputInLog: Bool = false) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.runInBackground = runInBackground
        self.copyURLFromOutput = copyURLFromOutput
        self.copyOutputToClipboard = copyOutputToClipboard
        self.format = format
        self.showOutputInLog = showOutputInLog
    }

    /// Upstream ships Paint and Paint.NET; the Mac's built-in image app is Preview.
    public static let defaults = [ExternalCommand(name: "Preview", command: "/usr/bin/open", arguments: "-a Preview \"{0}\"")]

    enum CodingKeys: String, CodingKey {
        case id, name, command, arguments, runInBackground, copyURLFromOutput, copyOutputToClipboard, format, showOutputInLog
    }

    /// Every value falls back to its default, so commands saved before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        id = value(.id, UUID())
        name = value(.name, "")
        command = value(.command, "")
        arguments = value(.arguments, "\"{0}\"")
        runInBackground = value(.runInBackground, true)
        copyURLFromOutput = value(.copyURLFromOutput, true)
        copyOutputToClipboard = value(.copyOutputToClipboard, false)
        // A command gets a plain image, never a .greenshot file.
        format = value(.format, ImageFormat.png).plainImage
        showOutputInLog = value(.showOutputInLog, false)
    }
}

/// Upstream PDF plugin settings (`IPdfConfiguration.cs`).
public struct PDFSettings: Codable, Equatable, Sendable {
    public enum PageSize: String, Codable, CaseIterable, Sendable {
        case image, custom, a3, a4, a5, a6, letter

        public var displayName: String {
            switch self {
            case .image: return String(localized: "Image size", comment: "PDF page size: the size of the image")
            case .custom: return String(localized: "pdf.pageSize.custom", defaultValue: "Custom", comment: "PDF page size: a width and height the user enters")
            case .a3: return "A3"
            case .a4: return "A4"
            case .a5: return "A5"
            case .a6: return "A6"
            case .letter: return String(localized: "Letter", comment: "PDF page size: US Letter paper")
            }
        }
    }

    public enum Unit: String, Codable, CaseIterable, Sendable {
        case mm, cm, inch

        public var displayName: String {
            self == .inch ? String(localized: "inch", comment: "Unit of the PDF page size") : rawValue
        }
        /// PDF points per unit.
        public var points: Double {
            switch self {
            case .mm: return 72 / 25.4
            case .cm: return 72 / 2.54
            case .inch: return 72
            }
        }
    }

    public enum Scaling: String, Codable, CaseIterable, Sendable {
        case shrinkToFit, fitToPage

        public var displayName: String {
            switch self {
            case .shrinkToFit: return String(localized: "Only shrink to fit")
            case .fitToPage: return String(localized: "Fit to page")
            }
        }
    }

    public var pageSize: PageSize = .image
    public var unit: Unit = .mm
    public var customWidth: Double = 210
    public var customHeight: Double = 297
    public var marginTop: Double = 0
    public var marginLeft: Double = 0
    public var marginRight: Double = 0
    public var marginBottom: Double = 0
    public var scaling: Scaling = .shrinkToFit

    public init() {}

    enum CodingKeys: String, CodingKey {
        case pageSize, unit, customWidth, customHeight, marginTop, marginLeft, marginRight, marginBottom, scaling
    }

    /// Every value falls back to its default, so settings written before a new option, or with a choice of a newer
    /// version, still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PDFSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        pageSize = value(.pageSize, d.pageSize)
        unit = value(.unit, d.unit)
        customWidth = value(.customWidth, d.customWidth)
        customHeight = value(.customHeight, d.customHeight)
        marginTop = value(.marginTop, d.marginTop)
        marginLeft = value(.marginLeft, d.marginLeft)
        marginRight = value(.marginRight, d.marginRight)
        marginBottom = value(.marginBottom, d.marginBottom)
        scaling = value(.scaling, d.scaling)
    }
}

// MARK: Uploads

/// Upstream Jira plugin settings (`IJiraConfiguration.cs`). The API token is in the Keychain, not here.
public struct JiraSettings: Codable, Equatable, Sendable {
    /// e.g. `https://yourcompany.atlassian.net`; empty means not set up.
    public var url = ""
    /// The Atlassian account the API token belongs to.
    public var email = ""
    public var uploadFormat: UploadFormat = .png
    public var jpegQuality = 80
    /// The issues uploaded to, newest first (upstream remembers the issues seen in browser titles).
    public var recentIssueKeys: [String] = []
    /// Reduce the uploaded image to at most 256 colours (upstream `UploadReduceColors`).
    public var reduceColors = false
    /// How Greenshot signs in: an Atlassian Cloud API token, or a Server/Data Center token or password.
    public var login: AtlassianLogin = .cloudAPIToken

    public static let maxRecentIssueKeys = 10

    public init() {}

    enum CodingKeys: String, CodingKey { case url, email, uploadFormat, jpegQuality, recentIssueKeys, reduceColors, login }

    /// Every value falls back to its default, so settings written before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JiraSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        url = value(.url, d.url)
        email = value(.email, d.email)
        uploadFormat = value(.uploadFormat, d.uploadFormat)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        recentIssueKeys = value(.recentIssueKeys, d.recentIssueKeys)
        reduceColors = value(.reduceColors, d.reduceColors)
        login = value(.login, d.login)
    }

    public mutating func remember(issueKey: String) {
        recentIssueKeys.removeAll { $0 == issueKey }
        recentIssueKeys.insert(issueKey, at: 0)
        if recentIssueKeys.count > Self.maxRecentIssueKeys { recentIssueKeys.removeLast(recentIssueKeys.count - Self.maxRecentIssueKeys) }
    }
}

/// Upstream Confluence plugin settings (`IConfluenceConfiguration.cs`). The API token is in the Keychain.
public struct ConfluenceSettings: Codable, Equatable, Sendable {
    public enum ClipboardContent: String, Codable, CaseIterable, Sendable {
        case nothing, wikiMarkup, imageLink

        public var displayName: String {
            switch self {
            case .nothing: return String(localized: "Nothing", comment: "What goes to the clipboard after a Confluence upload: nothing")
            case .wikiMarkup: return String(localized: "Wiki markup (!name!)")
            case .imageLink: return String(localized: "Link to the image")
            }
        }
    }

    /// e.g. `https://yourcompany.atlassian.net/wiki`; empty means not set up.
    public var url = ""
    public var email = ""
    public var uploadFormat: UploadFormat = .png
    public var jpegQuality = 80
    public var openPageAfterUpload = true
    /// Upstream `CopyWikiMarkupForImageToClipboard`, with the image's link as the other choice.
    public var clipboardContent: ClipboardContent = .wikiMarkup
    /// The pages uploaded to, newest first.
    public var recentPages: [ConfluencePage] = []
    /// The space the page search was limited to last time; empty searches every space (upstream `SearchSpaceKey`).
    public var searchSpaceKey = ""
    /// Reduce the uploaded image to at most 256 colours (upstream `UploadReduceColors`).
    public var reduceColors = false
    /// How Greenshot signs in: an Atlassian Cloud API token, or a Server/Data Center token or password.
    public var login: AtlassianLogin = .cloudAPIToken
    /// Include personal spaces in the search and the browse tree (upstream `IncludePersonSpaces`).
    public var includePersonalSpaces = false

    public static let maxRecentPages = 10

    public init() {}

    enum CodingKeys: String, CodingKey {
        case url, email, uploadFormat, jpegQuality, openPageAfterUpload, clipboardContent, recentPages, searchSpaceKey, reduceColors
        case login, includePersonalSpaces
    }

    /// Every value falls back to its default, so settings written before a new option still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ConfluenceSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        url = value(.url, d.url)
        email = value(.email, d.email)
        uploadFormat = value(.uploadFormat, d.uploadFormat)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        openPageAfterUpload = value(.openPageAfterUpload, d.openPageAfterUpload)
        clipboardContent = value(.clipboardContent, d.clipboardContent)
        recentPages = value(.recentPages, d.recentPages)
        searchSpaceKey = value(.searchSpaceKey, d.searchSpaceKey)
        reduceColors = value(.reduceColors, d.reduceColors)
        login = value(.login, d.login)
        includePersonalSpaces = value(.includePersonalSpaces, d.includePersonalSpaces)
    }

    public mutating func remember(page: ConfluencePage) {
        recentPages.removeAll { $0.id == page.id }
        recentPages.insert(page, at: 0)
        if recentPages.count > Self.maxRecentPages { recentPages.removeLast(recentPages.count - Self.maxRecentPages) }
    }
}

/// Upstream Box plugin settings (`IBoxConfiguration.cs`), plus the user's own app (upstream ships Greenshot's
/// client ID, which this port can't use). The client secret and the tokens are in the Keychain.
public struct BoxSettings: Codable, Equatable, Sendable {
    public var clientID = ""
    public var uploadFormat: UploadFormat = .png
    public var jpegQuality = 80
    /// The folder to upload to ("0" is All Files).
    public var folderID = "0"
    public var copyLinkToClipboard = true
    /// A shared (open) link instead of the private one.
    public var useSharedLink = true

    public init() {}

    enum CodingKeys: String, CodingKey { case clientID, uploadFormat, jpegQuality, folderID, copyLinkToClipboard, useSharedLink }

    /// Every value falls back to its default, so settings written before a new option, or with a choice of a newer
    /// version, still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BoxSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        clientID = value(.clientID, d.clientID)
        uploadFormat = value(.uploadFormat, d.uploadFormat)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        folderID = value(.folderID, d.folderID)
        copyLinkToClipboard = value(.copyLinkToClipboard, d.copyLinkToClipboard)
        useSharedLink = value(.useSharedLink, d.useSharedLink)
    }
}

/// Upstream Dropbox plugin settings (`IDropboxConfiguration.cs`), plus the user's own app key. The tokens are in
/// the Keychain.
public struct DropboxSettings: Codable, Equatable, Sendable {
    public var appKey = ""
    public var uploadFormat: UploadFormat = .png
    public var jpegQuality = 80
    /// The folder to upload to, inside the app's folder or the Dropbox, e.g. "Screenshots"; empty is the root.
    public var folder = ""
    public var copyLinkToClipboard = true

    public init() {}

    enum CodingKeys: String, CodingKey { case appKey, uploadFormat, jpegQuality, folder, copyLinkToClipboard }

    /// Every value falls back to its default, so settings written before a new option, or with a choice of a newer
    /// version, still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DropboxSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        appKey = value(.appKey, d.appKey)
        uploadFormat = value(.uploadFormat, d.uploadFormat)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        folder = value(.folder, d.folder)
        copyLinkToClipboard = value(.copyLinkToClipboard, d.copyLinkToClipboard)
    }
}

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
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        case .center: return "Center"
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
        case .auto: return "The screen with the mouse"
        case .fullScreen: return "All screens"
        case .fixed: return "One screen"
        }
    }
}

/// Which messages are shown (upstream `NotificationLevel`).
public enum NotificationLevel: String, Codable, CaseIterable, Sendable {
    case all, warnings, errors, none

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .warnings: return "Warnings and errors"
        case .errors: return "Errors only"
        case .none: return "None"
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
}

/// Upstream `TornEdgeEffect`: ToothHeight 12, tooth ranges 20, all edges, GenerateShadow true.
public struct TornEdgeSettings: Codable, Equatable, Sendable {
    public var toothHeight: Int = 12
    public var horizontalToothRange: Int = 20
    public var verticalToothRange: Int = 20
    public var top = true
    public var left = true
    public var right = true
    public var bottom = true
    public var shadow = true

    public init(toothHeight: Int = 12, horizontalToothRange: Int = 20, verticalToothRange: Int = 20,
                top: Bool = true, left: Bool = true, right: Bool = true, bottom: Bool = true, shadow: Bool = true) {
        self.toothHeight = toothHeight
        self.horizontalToothRange = horizontalToothRange
        self.verticalToothRange = verticalToothRange
        self.top = top
        self.left = left
        self.right = right
        self.bottom = bottom
        self.shadow = shadow
    }
}

/// Upstream `TextObfuscationWindow` options (`TEXT_OBFUSCATION_FEATURE.md`).
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

    public init() {}
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
        case .html: return "HTML (image embedded)"
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
}

/// Upstream `MailApiTo/CC/BCC` and the Office plugin's `EmailSubjectPattern`.
public struct EmailSettings: Codable, Equatable, Sendable {
    public var to = ""
    public var cc = ""
    public var bcc = ""
    public var subjectPattern = "${title}"

    public init() {}
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

    public init(id: UUID = UUID(), name: String, command: String, arguments: String = "\"{0}\"",
                runInBackground: Bool = true, copyURLFromOutput: Bool = true, copyOutputToClipboard: Bool = false) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.runInBackground = runInBackground
        self.copyURLFromOutput = copyURLFromOutput
        self.copyOutputToClipboard = copyOutputToClipboard
    }

    /// Upstream ships Paint and Paint.NET; the Mac's built-in image app is Preview.
    public static let defaults = [ExternalCommand(name: "Preview", command: "/usr/bin/open", arguments: "-a Preview \"{0}\"")]
}

/// Upstream PDF plugin settings (`IPdfConfiguration.cs`).
public struct PDFSettings: Codable, Equatable, Sendable {
    public enum PageSize: String, Codable, CaseIterable, Sendable {
        case image, custom, a3, a4, a5, a6, letter

        public var displayName: String {
            switch self {
            case .image: return "Image size"
            case .custom: return "Custom"
            case .a3: return "A3"
            case .a4: return "A4"
            case .a5: return "A5"
            case .a6: return "A6"
            case .letter: return "Letter"
            }
        }
    }

    public enum Unit: String, Codable, CaseIterable, Sendable {
        case mm, cm, inch

        public var displayName: String { rawValue }
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
            case .shrinkToFit: return "Only shrink to fit"
            case .fitToPage: return "Fit to page"
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
}

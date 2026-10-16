// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where a capture goes (upstream "destinations").
public enum CaptureDestination: String, Codable, CaseIterable, Sendable {
    /// Ask with a menu after every capture (upstream "Picker", the default).
    case picker
    case editor
    case clipboard
    /// Save to the output folder with the filename pattern, without a dialog.
    case file
    /// Ask for a file name.
    case fileAs
    case printer

    public var displayName: String {
        switch self {
        case .picker: return "Ask every time"
        case .editor: return "Open in image editor"
        case .clipboard: return "Copy to clipboard"
        case .file: return "Save directly"
        case .fileAs: return "Save as…"
        case .printer: return "Print…"
        }
    }
}

public struct HotkeySettings: Codable, Equatable, Sendable {
    public var region: KeyCombo? = .defaultRegion
    public var window: KeyCombo? = .defaultWindow
    public var fullScreen: KeyCombo? = .defaultFullScreen
    public var lastRegion: KeyCombo? = .defaultLastRegion
    /// Upstream has no default for opening the clipboard either.
    public var clipboard: KeyCombo? = nil

    public init() {}

    enum CodingKeys: String, CodingKey { case region, window, fullScreen, lastRegion, clipboard }

    // A cleared hotkey is stored as null; a missing key (older settings) gets the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func combo(_ key: CodingKeys, _ fallback: KeyCombo?) -> KeyCombo? {
            guard c.contains(key) else { return fallback }
            return (try? c.decodeIfPresent(KeyCombo.self, forKey: key)) ?? nil
        }
        region = combo(.region, .defaultRegion)
        window = combo(.window, .defaultWindow)
        fullScreen = combo(.fullScreen, .defaultFullScreen)
        lastRegion = combo(.lastRegion, .defaultLastRegion)
        clipboard = combo(.clipboard, nil)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(region, forKey: .region)
        try c.encode(window, forKey: .window)
        try c.encode(fullScreen, forKey: .fullScreen)
        try c.encode(lastRegion, forKey: .lastRegion)
        try c.encode(clipboard, forKey: .clipboard)
    }
}

/// The settings, with upstream's defaults from `Greenshot.Base/Core/ICoreConfiguration.cs`.
public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkeys = HotkeySettings()
    public var destinations: [CaptureDestination] = [.picker]
    public var captureMousePointer = true
    /// Upstream "Use interactive window capture mode": the window hotkey opens the capture screen in window mode.
    public var interactiveWindowCapture = false
    /// macOS only: keep the window shadow (with transparency) in window captures.
    public var includeWindowShadow = false
    /// Milliseconds to wait before taking the picture, so menus and the hotkey's own effects are gone.
    public var captureDelayMilliseconds = 100
    public var playCameraSound = false
    public var showNotifications = true
    public var zoomerEnabled = true
    public var outputFolder = "~/Desktop"
    public var filenamePattern = FilenamePattern.defaultPattern
    public var outputFormat: ImageFormat = .png
    public var jpegQuality = 80
    /// After "Save directly", put the file's path on the clipboard (upstream `OutputFileCopyPathToClipboard`).
    public var copyPathToClipboard = true
    public var incrementingNumber: UInt = 1
    /// The last captured region, in Quartz global points, for "Capture last region".
    public var lastCapturedRegion: CGRect?
    /// The last used style per element kind (keyed by `AnnotationKind.rawValue`), like upstream's remembered fields.
    public var editorStyles: [String: AnnotationStyle] = [:]
    /// The emoji new emoji elements get: the last one picked (upstream `IEditorConfiguration.RecentEmoji`).
    public var recentEmoji = "🙂"

    public init() {}

    public var outputFolderURL: URL {
        URL(fileURLWithPath: (outputFolder as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func style(for kind: AnnotationKind) -> AnnotationStyle {
        editorStyles[kind.rawValue] ?? .defaults(for: kind)
    }

    enum CodingKeys: String, CodingKey {
        case hotkeys, destinations, captureMousePointer, interactiveWindowCapture, includeWindowShadow, captureDelayMilliseconds
        case playCameraSound, showNotifications, zoomerEnabled, outputFolder, filenamePattern, outputFormat, jpegQuality
        case copyPathToClipboard, incrementingNumber, lastCapturedRegion, editorStyles, recentEmoji
    }

    // Every value falls back to its default, so settings written by another version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        hotkeys = value(.hotkeys, d.hotkeys)
        destinations = value(.destinations, d.destinations)
        captureMousePointer = value(.captureMousePointer, d.captureMousePointer)
        interactiveWindowCapture = value(.interactiveWindowCapture, d.interactiveWindowCapture)
        includeWindowShadow = value(.includeWindowShadow, d.includeWindowShadow)
        captureDelayMilliseconds = value(.captureDelayMilliseconds, d.captureDelayMilliseconds)
        playCameraSound = value(.playCameraSound, d.playCameraSound)
        showNotifications = value(.showNotifications, d.showNotifications)
        zoomerEnabled = value(.zoomerEnabled, d.zoomerEnabled)
        outputFolder = value(.outputFolder, d.outputFolder)
        filenamePattern = value(.filenamePattern, d.filenamePattern)
        outputFormat = value(.outputFormat, d.outputFormat)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        copyPathToClipboard = value(.copyPathToClipboard, d.copyPathToClipboard)
        incrementingNumber = value(.incrementingNumber, d.incrementingNumber)
        lastCapturedRegion = value(.lastCapturedRegion, d.lastCapturedRegion)
        editorStyles = value(.editorStyles, d.editorStyles)
        recentEmoji = value(.recentEmoji, d.recentEmoji)
    }
}

public enum SettingsStorage {
    public static let key = "settings.v1"

    public static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public static func save(_ settings: AppSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

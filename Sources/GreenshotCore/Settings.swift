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
    /// A new mail with the image attached (upstream `EmailDestination`).
    case email
    /// The macOS share menu (upstream `Win10ShareDestination`).
    case share
    /// The text in the image to the clipboard (upstream `Win10OcrDestination`).
    case ocr
    /// The External Command plugin: run a configured command with the image file.
    case externalCommand
    /// The PDF plugin.
    case pdf
    /// Open the image file with another application (the Mac's stand-in for the Office destinations).
    case openWith
    /// The Office plugin on the Mac (AppleScript): insert into Word, Excel or PowerPoint, a new mail in Outlook, and Notes
    /// as the stand-in for OneNote.
    case word, excel, powerpoint, outlook, notes
    /// The Zxing plugin's QR code actions: copy or open what a QR code in the image says.
    case qrCode
    /// The upload plugins: attach to a Jira issue or a Confluence page, upload to Box or Dropbox.
    case jira
    case confluence
    case box
    case dropbox

    public var displayName: String {
        switch self {
        case .picker: return "Ask every time"
        case .editor: return "Open in image editor"
        case .clipboard: return "Copy to clipboard"
        case .file: return "Save directly"
        case .fileAs: return "Save as…"
        case .printer: return "Print…"
        case .email: return "Email…"
        case .share: return "Share…"
        case .ocr: return "Copy text (OCR)"
        case .externalCommand: return "External command"
        case .pdf: return "Save as PDF"
        case .openWith: return "Open with…"
        case .word: return "Insert into Microsoft Word"
        case .excel: return "Insert into Microsoft Excel"
        case .powerpoint: return "Insert into Microsoft PowerPoint"
        case .outlook: return "New email in Microsoft Outlook"
        case .notes: return "New note in Notes"
        case .qrCode: return "QR code actions"
        case .jira: return "Upload to Jira…"
        case .confluence: return "Upload to Confluence…"
        case .box: return "Upload to Box"
        case .dropbox: return "Upload to Dropbox"
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
    /// Starts a screen recording of the target in Settings › Video, or stops the running one. No default.
    public var recordVideo: KeyCombo? = nil
    /// "Capture text": the capture screen in text mode, the text goes to the clipboard (upstream's built-in recipe
    /// "OCR text to clipboard"). No default, like upstream.
    public var text: KeyCombo? = nil

    public init() {}

    enum CodingKeys: String, CodingKey { case region, window, fullScreen, lastRegion, clipboard, text, recordVideo }

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
        text = combo(.text, nil)
        recordVideo = combo(.recordVideo, nil)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(region, forKey: .region)
        try c.encode(window, forKey: .window)
        try c.encode(fullScreen, forKey: .fullScreen)
        try c.encode(lastRegion, forKey: .lastRegion)
        try c.encode(clipboard, forKey: .clipboard)
        try c.encode(text, forKey: .text)
        try c.encode(recordVideo, forKey: .recordVideo)
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
    /// Window mode also selects the areas inside a window, like a sidebar, a toolbar or a part of a web page, read with
    /// the Accessibility permission; PgUp and PgDn select the larger or smaller area (upstream: for beta testers,
    /// `IsBetaTester` turns on `WindowCaptureTool.SelectsAreas`).
    public var windowCaptureSelectsAreas = false
    /// HDR screens (macOS 15 or later): the bright parts of HDR videos, photos and games are tone mapped into the
    /// screenshot instead of cut off; captures without HDR content keep their colours exactly (upstream
    /// `UseGraphicsCapture`, which upstream needs for HDR screens).
    public var toneMapHDRCaptures = true
    /// Milliseconds to wait before taking the picture, so menus and the hotkey's own effects are gone.
    public var captureDelayMilliseconds = 100
    public var playCameraSound = false
    /// The sound file played after a capture (upstream `NotificationSound`); empty plays the built-in camera sound.
    public var notificationSound = ""
    public var showNotifications = true
    /// Show a Dock icon (and be in ⌘Tab) while an editor or Settings is open. Without windows Greenshot is a menu bar
    /// app either way, like its tray icon on Windows. Off: never a Dock icon, and opening an editor from a full screen
    /// app doesn't switch to the desktop.
    public var dockIconWhileWindowOpen = true
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

    // Capture screen (upstream `FixedCaptureSizes`, `RecentCaptureSizes`, `FixedCaptureSize`, `FixedCaptureAnchor`,
    // `ScreenCaptureMode`, `ScreenToCapture`, `CaptureHelpVisible`, `CaptureInfoVisible`,
    // `CaptureSelectionPreviewVisible`, `ZoomerShowsPreview`, `OcrLanguage`, `ScanOnCapture`, `AutoCropDifference`).
    public var fixedCaptureSizes: [CaptureSize] = CaptureSize.defaults
    /// The last five region sizes, newest first.
    public var recentCaptureSizes: [CaptureSize] = []
    /// The size the fixed-size mode last used.
    public var fixedCaptureSize: CaptureSize?
    public var fixedCaptureAnchor: FixedCaptureAnchor = .topLeft
    public var screenCaptureMode: ScreenCaptureMode = .auto
    /// 1-based, for `screenCaptureMode == .fixed`.
    public var screenToCapture = 1
    public var captureHelpVisible = true
    public var captureInfoVisible = true
    public var captureSelectionPreviewVisible = true
    /// The preview of the selection is in the place of the zoomer instead of a corner (upstream `ZoomerShowsPreview`).
    public var zoomerShowsPreview = false
    /// How see-through the zoomer is, from 0 (invisible) to 1 (solid) (upstream `ZoomerOpacity`).
    public var zoomerOpacity: Double = 1
    /// A BCP 47 language for text recognition; empty means automatic.
    public var ocrLanguage = ""
    /// Recognise the text of the screens as soon as the capture screen opens, so the text mode (T) has its lines at
    /// once (upstream `AlwaysRunOCROnCapture`).
    public var alwaysRunOCROnCapture = false
    /// Look for QR codes on the capture screen.
    public var scanQRCodesOnCapture = true
    /// Colour difference (0–255) that auto crop treats as the same colour.
    public var autoCropDifference = 10
    public var notificationLevel: NotificationLevel = .all
    /// Show a thumbnail of the capture in the macOS notification after a capture (upstream `ShowNotificationThumbnail`,
    /// only offered where notifications can show captures). The capture is kept for a click on the notification either way.
    public var showNotificationThumbnail = true

    // Editor (upstream `IEditorConfiguration`).
    public var reuseEditor = false
    public var suppressSaveDialogAtClose = false
    public var matchSizeToCapture = true
    public var dropShadowSettings = DropShadowSettings()
    public var tornEdgeSettings = TornEdgeSettings()
    public var textObfuscation = TextObfuscationSettings()
    /// The crop bar's "Cut edges": the edges of the sides a crop cuts off, and how the joint is marked after cutting
    /// rows or columns out (upstream's `CUT_MARK_STYLE` field of the crop).
    public var cutOutMarkStyle: CutMarkStyle = .none
    /// Freehand smoothing: a drawn point is kept when it is at least twice this many points from the last one; smaller
    /// is more detailed (upstream `FreehandSensitivity`, 1–100).
    public var freehandSensitivity = 3
    /// The size of File › New Image, in points (upstream `DefaultEditorSize`).
    public var defaultEditorSize = CaptureSize(width: 500, height: 500)

    // Output (upstream `OutputFile*`, `ClipboardFormats`, `OutputPrint*`, mail and the plugins).
    public var allowOverwrite = true
    public var promptJpegQuality = false
    public var reduceColors = false
    public var reduceColorsTo = 256
    /// Write an 8-bit (palette) image when an opaque image has fewer than 256 colours (upstream
    /// `OutputFileAutoReduceColors`).
    public var autoReduceColors = false
    public var clipboardFormats: [ClipboardFormat] = ClipboardFormat.defaults
    public var printing = PrintSettings()
    public var email = EmailSettings()
    public var externalCommands: [ExternalCommand] = ExternalCommand.defaults
    public var pdf = PDFSettings()
    public var jira = JiraSettings()
    public var confluence = ConfluenceSettings()
    public var box = BoxSettings()
    public var dropbox = DropboxSettings()
    /// Days between update checks; 0 never checks (upstream `UpdateCheckInterval`, 14).
    public var updateCheckIntervalDays = 14
    public var lastUpdateCheck: Date?
    /// The last file "Save directly" or "Save as" wrote, for "Open recent capture".
    public var lastSavedFile: String?

    // Menu bar icon and app (upstream `LeftClickAction`, `DoubleClickAction`, `HideTrayicon`, `ThumnailPreview`,
    // `MaxMenuItemLength`, `Theme`, `CheckForUnstable`).
    /// What a click on the menu bar icon does; right-click and ⌃-click always show the menu.
    public var leftClickAction: ClickAction = .showMenu
    /// What a double-click on the menu bar icon does; only when a click doesn't show the menu, and then a click waits
    /// for the double-click time.
    public var doubleClickAction: ClickAction = .openLastInFinder
    /// Run without the menu bar icon; opening the app again shows Settings.
    public var hideMenuBarIcon = false
    /// Show a picture of the window while pointing at it in a window list menu.
    public var thumbnailPreview = true
    /// Window titles in menus are cut to this many characters.
    public var maxMenuItemLength = 25
    /// The colours of the app's windows: as macOS, light or dark.
    public var theme: AppTheme = .system
    /// Also offer pre-release (beta) updates.
    public var checkForUnstable = false
    /// The welcome window was shown; it is shown once, at the first start (upstream `WelcomeShown`).
    public var welcomeShown = false

    // Destinations (upstream `IOfficeConfiguration`, `AllowedUntrustedCertificateHosts`, `AllowedCertificateThumbprints`).
    /// The Office plugin's options (Word, PowerPoint, Outlook); To, CC, BCC and the subject are `email`'s.
    public var office = OfficeSettings()
    /// Servers whose certificate is accepted although macOS doesn't trust it (self-signed Jira or Confluence servers);
    /// `*.example.com` matches the subdomains (upstream `AllowedUntrustedCertificateHosts`).
    public var allowedUntrustedCertificateHosts: [String] = []
    /// Certificates accepted by their SHA-1 or SHA-256 fingerprint, colons and spaces allowed (upstream
    /// `AllowedCertificateThumbprints`).
    public var allowedCertificateThumbprints: [String] = []

    /// Screen recordings (Settings › Video).
    public var video = VideoSettings()
    /// The recipe settings (upstream greenshot.ini `[Recipe]` and `[RecipeOptions]`).
    public var recipes = RecipeSettings()
    /// Mac-only: greenshotmac://capture/… and greenshotmac://clipboard links (from web pages, Alfred, Raycast) may take a
    /// screenshot or open the clipboard; off, as any web page can open a link.
    public var automationAllowCaptureLinks = false
    /// AI tools: greenshot-mcp, consent, excluded applications (Settings › AI Tools; upstream ICoreConfiguration AiTools*).
    public var aiTools = AIToolsSettings()
    /// The browser extension may connect (Settings › Expert › Browser extension). Off: every request of the native
    /// messaging host is refused and the host can't be installed. Mac only (an administrator's off switch).
    public var browserExtensionEnabled = true

    // Admin policy (upstream `ICoreConfiguration.DisableSettings`, `DisableQuickSettings`, `HideExpertSettings`,
    // `ExcludeDestinations`): no controls; set by a configuration profile, see docs/admin. Forced values are never saved.
    /// Settings can't be opened: its menu items are hidden and every other way to open it says why.
    public var disableSettings = false
    /// The menu bar menu has no Quick Settings.
    public var disableQuickSettings = false
    /// Settings has no Expert tab.
    public var hideExpertSettings = false
    /// Destinations that are hidden and refused everywhere: `CaptureDestination` raw values, upstream's designations or
    /// plugin names, any case (upstream `ExcludeDestinations` and `ExcludePlugins`).
    public var excludeDestinations: [String] = []

    public init() {}

    public var outputFolderURL: URL {
        URL(fileURLWithPath: (outputFolder as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Turns a destination on or off. "Ask every time" (upstream's picker) excludes the others: turning it on turns
    /// them off, turning on another turns it off, and with no destination left it comes back.
    public mutating func setDestination(_ destination: CaptureDestination, on: Bool) {
        if on {
            if destination == .picker {
                destinations = [.picker]
            } else if !destinations.contains(destination) {
                destinations = destinations.filter { $0 != .picker } + [destination]
            }
        } else {
            destinations.removeAll { $0 == destination }
        }
        if destinations.isEmpty { destinations = [.picker] }
    }

    public func style(for kind: AnnotationKind) -> AnnotationStyle {
        editorStyles[kind.rawValue] ?? .defaults(for: kind)
    }

    enum CodingKeys: String, CodingKey {
        case hotkeys, destinations, captureMousePointer, interactiveWindowCapture, includeWindowShadow, captureDelayMilliseconds
        case windowCaptureSelectsAreas, toneMapHDRCaptures, showNotificationThumbnail, welcomeShown
        case office, allowedUntrustedCertificateHosts, allowedCertificateThumbprints
        case video, recipes, automationAllowCaptureLinks, aiTools, browserExtensionEnabled
        case disableSettings, disableQuickSettings, hideExpertSettings, excludeDestinations
        case playCameraSound, notificationSound, showNotifications, dockIconWhileWindowOpen, zoomerEnabled, outputFolder, filenamePattern, outputFormat, jpegQuality
        case copyPathToClipboard, incrementingNumber, lastCapturedRegion, editorStyles, recentEmoji
        case fixedCaptureSizes, recentCaptureSizes, fixedCaptureSize, fixedCaptureAnchor, screenCaptureMode, screenToCapture
        case captureHelpVisible, captureInfoVisible, captureSelectionPreviewVisible, zoomerShowsPreview, zoomerOpacity, ocrLanguage
        case alwaysRunOCROnCapture, scanQRCodesOnCapture
        case autoCropDifference, notificationLevel
        case reuseEditor, suppressSaveDialogAtClose, matchSizeToCapture, dropShadowSettings, tornEdgeSettings, textObfuscation
        case cutOutMarkStyle, freehandSensitivity, defaultEditorSize
        case allowOverwrite, promptJpegQuality, reduceColors, reduceColorsTo, autoReduceColors, clipboardFormats, printing, email, externalCommands, pdf
        case jira, confluence, box, dropbox
        case updateCheckIntervalDays, lastUpdateCheck, lastSavedFile
        case leftClickAction, doubleClickAction, hideMenuBarIcon, thumbnailPreview, maxMenuItemLength, theme, checkForUnstable
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
        windowCaptureSelectsAreas = value(.windowCaptureSelectsAreas, d.windowCaptureSelectsAreas)
        toneMapHDRCaptures = value(.toneMapHDRCaptures, d.toneMapHDRCaptures)
        showNotificationThumbnail = value(.showNotificationThumbnail, d.showNotificationThumbnail)
        welcomeShown = value(.welcomeShown, d.welcomeShown)
        office = value(.office, d.office)
        allowedUntrustedCertificateHosts = value(.allowedUntrustedCertificateHosts, d.allowedUntrustedCertificateHosts)
        allowedCertificateThumbprints = value(.allowedCertificateThumbprints, d.allowedCertificateThumbprints)
        video = value(.video, d.video)
        recipes = value(.recipes, d.recipes)
        automationAllowCaptureLinks = value(.automationAllowCaptureLinks, d.automationAllowCaptureLinks)
        aiTools = value(.aiTools, d.aiTools)
        browserExtensionEnabled = value(.browserExtensionEnabled, d.browserExtensionEnabled)
        disableSettings = value(.disableSettings, d.disableSettings)
        disableQuickSettings = value(.disableQuickSettings, d.disableQuickSettings)
        hideExpertSettings = value(.hideExpertSettings, d.hideExpertSettings)
        excludeDestinations = value(.excludeDestinations, d.excludeDestinations)
        captureDelayMilliseconds = value(.captureDelayMilliseconds, d.captureDelayMilliseconds)
        playCameraSound = value(.playCameraSound, d.playCameraSound)
        notificationSound = value(.notificationSound, d.notificationSound)
        showNotifications = value(.showNotifications, d.showNotifications)
        dockIconWhileWindowOpen = value(.dockIconWhileWindowOpen, d.dockIconWhileWindowOpen)
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
        fixedCaptureSizes = value(.fixedCaptureSizes, d.fixedCaptureSizes)
        recentCaptureSizes = value(.recentCaptureSizes, d.recentCaptureSizes)
        fixedCaptureSize = value(.fixedCaptureSize, d.fixedCaptureSize)
        fixedCaptureAnchor = value(.fixedCaptureAnchor, d.fixedCaptureAnchor)
        screenCaptureMode = value(.screenCaptureMode, d.screenCaptureMode)
        screenToCapture = value(.screenToCapture, d.screenToCapture)
        captureHelpVisible = value(.captureHelpVisible, d.captureHelpVisible)
        captureInfoVisible = value(.captureInfoVisible, d.captureInfoVisible)
        captureSelectionPreviewVisible = value(.captureSelectionPreviewVisible, d.captureSelectionPreviewVisible)
        zoomerShowsPreview = value(.zoomerShowsPreview, d.zoomerShowsPreview)
        zoomerOpacity = value(.zoomerOpacity, d.zoomerOpacity)
        ocrLanguage = value(.ocrLanguage, d.ocrLanguage)
        alwaysRunOCROnCapture = value(.alwaysRunOCROnCapture, d.alwaysRunOCROnCapture)
        scanQRCodesOnCapture = value(.scanQRCodesOnCapture, d.scanQRCodesOnCapture)
        autoCropDifference = value(.autoCropDifference, d.autoCropDifference)
        notificationLevel = value(.notificationLevel, d.notificationLevel)
        reuseEditor = value(.reuseEditor, d.reuseEditor)
        suppressSaveDialogAtClose = value(.suppressSaveDialogAtClose, d.suppressSaveDialogAtClose)
        matchSizeToCapture = value(.matchSizeToCapture, d.matchSizeToCapture)
        dropShadowSettings = value(.dropShadowSettings, d.dropShadowSettings)
        tornEdgeSettings = value(.tornEdgeSettings, d.tornEdgeSettings)
        textObfuscation = value(.textObfuscation, d.textObfuscation)
        cutOutMarkStyle = value(.cutOutMarkStyle, d.cutOutMarkStyle)
        freehandSensitivity = value(.freehandSensitivity, d.freehandSensitivity)
        defaultEditorSize = value(.defaultEditorSize, d.defaultEditorSize)
        allowOverwrite = value(.allowOverwrite, d.allowOverwrite)
        promptJpegQuality = value(.promptJpegQuality, d.promptJpegQuality)
        reduceColors = value(.reduceColors, d.reduceColors)
        reduceColorsTo = value(.reduceColorsTo, d.reduceColorsTo)
        autoReduceColors = value(.autoReduceColors, d.autoReduceColors)
        clipboardFormats = value(.clipboardFormats, d.clipboardFormats)
        printing = value(.printing, d.printing)
        email = value(.email, d.email)
        externalCommands = value(.externalCommands, d.externalCommands)
        pdf = value(.pdf, d.pdf)
        jira = value(.jira, d.jira)
        confluence = value(.confluence, d.confluence)
        box = value(.box, d.box)
        dropbox = value(.dropbox, d.dropbox)
        updateCheckIntervalDays = value(.updateCheckIntervalDays, d.updateCheckIntervalDays)
        lastUpdateCheck = value(.lastUpdateCheck, d.lastUpdateCheck)
        lastSavedFile = value(.lastSavedFile, d.lastSavedFile)
        leftClickAction = value(.leftClickAction, d.leftClickAction)
        doubleClickAction = value(.doubleClickAction, d.doubleClickAction)
        hideMenuBarIcon = value(.hideMenuBarIcon, d.hideMenuBarIcon)
        thumbnailPreview = value(.thumbnailPreview, d.thumbnailPreview)
        maxMenuItemLength = value(.maxMenuItemLength, d.maxMenuItemLength)
        theme = value(.theme, d.theme)
        checkForUnstable = value(.checkForUnstable, d.checkForUnstable)
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

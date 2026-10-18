// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where `user.*`, `machine.*`, `config.*` and the clock come from. Tests pass fixed values; the app passes
/// `SystemRecipeEnvironment` with a snapshot of the settings.
public protocol RecipeEnvironment: Sendable {
    /// `user.username`, `user.desktop`, ... (upstream `ResolveUserEnvironment`, macOS folders), then the environment.
    func userValue(_ key: String) -> JSONValue?
    /// `machine.computername`, `machine.os`, ... (upstream `ResolveMachineEnvironment`; Windows-only names are empty).
    func machineValue(_ key: String) -> JSONValue?
    /// `config.<name>`: a setting by its upstream `greenshot.ini` name or its Mac name, case-insensitive; read-only.
    func configValue(_ key: String) -> JSONValue?
    func now() -> Date
    var timeZone: TimeZone { get }
}

/// The real environment: NSUserName, the user's folders, ProcessInfo, and `config.*` from the settings snapshot through
/// a table of upstream names (`language`, `capturemousepointer`, `outputfilepath`, ...).
public struct SystemRecipeEnvironment: RecipeEnvironment {
    private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func userValue(_ key: String) -> JSONValue? {
        let files = FileManager.default
        func folder(_ directory: FileManager.SearchPathDirectory) -> JSONValue? {
            files.urls(for: directory, in: .userDomainMask).first.map { .string($0.path) }
        }
        switch key.lowercased() {
        case "name", "username": return .string(NSUserName())
        // Upstream: the domain, which is the computer name for a local account.
        case "domain", "userdomain": return .string(FilenamePattern.Context.shortHostName())
        case "profile", "userprofile": return .string(NSHomeDirectory())
        case "appdata", "roamingappdata", "localappdata": return folder(.applicationSupportDirectory)
        case "desktop": return folder(.desktopDirectory)
        case "documents", "mydocuments": return folder(.documentDirectory)
        case "pictures", "mypictures": return folder(.picturesDirectory)
        case "temp": return .string(NSTemporaryDirectory())
        default: return Self.environmentVariable(key)
        }
    }

    public func machineValue(_ key: String) -> JSONValue? {
        switch key.lowercased() {
        case "name", "machinename", "computername": return .string(FilenamePattern.Context.shortHostName())
        case "os", "osdescription": return .string("macOS")
        case "osversion": return .string(ProcessInfo.processInfo.operatingSystemVersionString)
        case "processors", "processorcount": return .number(Double(ProcessInfo.processInfo.processorCount))
        case "is64bit", "is64bitoperatingsystem": return .bool(true)
        case "systemdir", "systemdirectory": return .string("/System/Library")
        case "programfiles": return .string("/Applications")
        case "commonappdata": return .string("/Library/Application Support")
        default: return Self.environmentVariable(key)
        }
    }

    public func configValue(_ key: String) -> JSONValue? {
        let lower = key.lowercased()
        if let read = Self.upstreamNames[lower] { return read(settings) }
        return Self.macSetting(lower, of: settings)
    }

    public func now() -> Date { Date() }
    public var timeZone: TimeZone { .current }

    private static func environmentVariable(_ key: String) -> JSONValue? {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment[key] ?? environment[key.uppercased()] { return .string(value) }
        return nil
    }

    /// `config.<name>` by the upstream `ICoreConfiguration` property names (greenshot.ini [Core]), lowercased.
    private static let upstreamNames: [String: @Sendable (AppSettings) -> JSONValue] = [
        // Upstream `ICoreConfiguration.Language`: the code of the language in use ("de-DE").
        "language": { _ in .string(LanguagePacks.inUse().ietf) },
        "capturemousepointer": { .bool($0.captureMousePointer) },
        "capturewindowsinteractive": { .bool($0.interactiveWindowCapture) },
        "capturedelay": { .number(Double($0.captureDelayMilliseconds)) },
        "screencapturemode": { .string($0.screenCaptureMode.rawValue) },
        "screentocapture": { .number(Double($0.screenToCapture)) },
        "playcamerasound": { .bool($0.playCameraSound) },
        "showtraynotification": { .bool($0.showNotifications) },
        "notificationlevel": { .string($0.notificationLevel.rawValue) },
        "shownotificationthumbnail": { .bool($0.showNotificationThumbnail) },
        "outputdestinations": { .array($0.destinations.map { .string(RecipeDestinationDesignation.designation(for: $0)) }) },
        "outputfilepath": { .string($0.outputFolderURL.path) },
        "outputfileallowoverwrite": { .bool($0.allowOverwrite) },
        "outputfilefilenamepattern": { .string($0.filenamePattern) },
        "outputfileformat": { .string($0.outputFormat.rawValue) },
        "outputfilereducecolors": { .bool($0.reduceColors) },
        "outputfileautoreducecolors": { .bool($0.autoReduceColors) },
        "outputfilereducecolorsto": { .number(Double($0.reduceColorsTo)) },
        "outputfilecopypathtoclipboard": { .bool($0.copyPathToClipboard) },
        "outputfilejpegquality": { .number(Double($0.jpegQuality)) },
        "outputfilepromptquality": { .bool($0.promptJpegQuality) },
        "outputfileincrementingnumber": { .number(Double($0.incrementingNumber)) },
        "notificationsound": { .string($0.notificationSound) },
        "autocropdifference": { .number(Double($0.autoCropDifference)) },
        "updatecheckinterval": { .number(Double($0.updateCheckIntervalDays)) },
        "checkforunstable": { .bool($0.checkForUnstable) },
        "hidetrayicon": { .bool($0.hideMenuBarIcon) },
        "thumnailpreview": { .bool($0.thumbnailPreview) },
        "welcomeshown": { .bool($0.welcomeShown) },
        "zoomerenabled": { .bool($0.zoomerEnabled) },
        "zoomeropacity": { .number($0.zoomerOpacity) },
        "capturehelpvisible": { .bool($0.captureHelpVisible) },
        "captureinfovisible": { .bool($0.captureInfoVisible) },
        "captureselectionpreviewvisible": { .bool($0.captureSelectionPreviewVisible) },
        "zoomershowspreview": { .bool($0.zoomerShowsPreview) },
        "maxmenuitemlength": { .number(Double($0.maxMenuItemLength)) },
        "leftclickaction": { .string($0.leftClickAction.rawValue) },
        "doubleclickaction": { .string($0.doubleClickAction.rawValue) },
        "theme": { .string($0.theme.rawValue) },
        "recipefiles": { .string($0.recipes.files.joined(separator: ";")) }
    ]

    /// `config.<name>` by the Mac's setting name: plain values only (no nested settings).
    private static func macSetting(_ lower: String, of settings: AppSettings) -> JSONValue? {
        for child in Mirror(reflecting: settings).children {
            guard let label = child.label, label.lowercased() == lower else { continue }
            return plainValue(child.value)
        }
        return nil
    }

    private static func plainValue(_ value: Any) -> JSONValue? {
        switch value {
        case let flag as Bool: return .bool(flag)
        case let number as Int: return .number(Double(number))
        case let number as UInt: return .number(Double(number))
        case let number as Double: return .number(number)
        case let number as CGFloat: return .number(Double(number))
        case let text as String: return .string(text)
        case let texts as [String]: return .array(texts.map(JSONValue.string))
        case let raw as any RawRepresentable:
            return (raw.rawValue as? String).map(JSONValue.string)
        default:
            return nil
        }
    }
}

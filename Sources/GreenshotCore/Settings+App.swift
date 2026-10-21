// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a click or double-click on the menu bar icon does: upstream `Greenshot.Base/Core/Enums/ClickActions.cs`
/// (`ICoreConfiguration.LeftClickAction`, `DoubleClickAction`), same cases in the same order.
public enum ClickAction: String, Codable, CaseIterable, Sendable {
    case doNothing
    /// Shows the last saved file in Finder (upstream `OPEN_LAST_IN_EXPLORER`).
    case openLastInFinder
    case openLastInEditor
    case openSettings
    /// Upstream `SHOW_CONTEXT_MENU`.
    case showMenu
    case captureRegion
    /// Every screen (upstream `CAPTURE_SCREEN`, `ScreenCaptureMode.FullScreen`).
    case captureScreen
    /// The image on the clipboard goes to the destinations, like a capture.
    case captureClipboard
    /// The capture screen in window mode.
    case captureWindow
    /// An editor with a blank image.
    case openEmptyEditor
    case openFileInEditor
    case openClipboardInEditor

    public var displayName: String {
        switch self {
        case .doNothing: return String(localized: "Do nothing")
        case .openLastInFinder: return String(localized: "Open last capture location")
        case .openLastInEditor: return String(localized: "Open last capture in the editor")
        case .openSettings: return String(localized: "Open Settings")
        case .showMenu: return String(localized: "Show the menu")
        case .captureRegion: return String(localized: "Capture region")
        case .captureScreen: return String(localized: "Capture full screen")
        case .captureClipboard: return String(localized: "Capture clipboard")
        case .captureWindow: return String(localized: "Capture window")
        case .openEmptyEditor: return String(localized: "Open an empty editor")
        case .openFileInEditor: return String(localized: "Open image from file")
        case .openClipboardInEditor: return String(localized: "Open image from clipboard")
        }
    }
}

/// The colours of the app's windows: upstream `Greenshot.Base/Core/Enums/UiTheme.cs` (`ICoreConfiguration.Theme`).
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    /// Follows System Settings › Appearance (upstream "Same as Windows").
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return String(localized: "Same as macOS")
        case .light: return String(localized: "Light", comment: "The light appearance of the app's windows (Settings › General › Theme)")
        case .dark: return String(localized: "Dark", comment: "The dark appearance of the app's windows (Settings › General › Theme)")
        }
    }
}

extension AppSettings {
    /// Whether notifications are on: Settings › Capture › Show notifications isn't None (upstream
    /// `AreNotificationsShown`). Quick Settings › Show Notifications has its tick then.
    public var notificationsShown: Bool { showNotifications && notificationLevel != .none }

    /// Quick Settings › Show Notifications (upstream's tray menu switch `ShowTrayNotification`): off turns
    /// `showNotifications` off and keeps the level, so on brings it back; on with the level None (Settings › Capture ›
    /// Show notifications = None sets both) brings back All, the default, so the tick really shows notifications.
    public mutating func setNotificationsShown(_ on: Bool) {
        showNotifications = on
        if on && notificationLevel == .none { notificationLevel = .all }
    }
}

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
        case .doNothing: return "Do nothing"
        case .openLastInFinder: return "Open last capture location"
        case .openLastInEditor: return "Open last capture in the editor"
        case .openSettings: return "Open Settings"
        case .showMenu: return "Show the menu"
        case .captureRegion: return "Capture region"
        case .captureScreen: return "Capture full screen"
        case .captureClipboard: return "Capture clipboard"
        case .captureWindow: return "Capture window"
        case .openEmptyEditor: return "Open an empty editor"
        case .openFileInEditor: return "Open image from file"
        case .openClipboardInEditor: return "Open image from clipboard"
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
        case .system: return "Same as macOS"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a click on the menu bar icon does: the decisions of upstream `Greenshot/Shell/TrayIcon.cs`
/// (`OnTrayLeftMouseUp`, the double-click timer), without the timer and the actions themselves.
public enum MenuBarClick {
    public enum Decision: Equatable, Sendable {
        case showMenu
        /// Run this action now (`doNothing` included: nothing to do).
        case run(ClickAction)
        /// A first click while there is a double-click action: wait the double-click time for a second click, then run
        /// the click action.
        case waitForSecondClick
        /// The second click came in time: stop waiting and run the double-click action.
        case runDoubleClick(ClickAction)
    }

    /// When a click shows the menu, the menu belongs to the icon and opens on mouse-down, like every Mac menu bar
    /// item. Upstream waits for a possible double-click even then; on a Mac that would make the menu feel slow, so the
    /// double-click action is not used in this case.
    public static func clickShowsMenu(_ clickAction: ClickAction) -> Bool {
        clickAction == .showMenu
    }

    /// A click on the icon while the menu doesn't belong to it.
    /// - Parameters:
    ///   - menuGesture: a right-click, a ⌃-click, or a press without the mouse (VoiceOver, keyboard): always the menu.
    ///   - waiting: an earlier click is waiting for its second click.
    public static func decide(menuGesture: Bool, waiting: Bool, click: ClickAction, doubleClick: ClickAction) -> Decision {
        if menuGesture || clickShowsMenu(click) { return .showMenu }
        // Without a double-click action the click needs no waiting (upstream: DO_NOTHING).
        if doubleClick == .doNothing { return .run(click) }
        return waiting ? .runDoubleClick(doubleClick) : .waitForSecondClick
    }
}

/// Texts of the menu bar menu.
public enum MenuBarText {
    /// "App – Title" for the window list. The title is cut to `maxLength` characters (upstream `MaxMenuItemLength`,
    /// `TrayMenu.cs` cuts the caption only), with "…" to show it was cut; a window without a title shows its app.
    public static func windowTitle(appName: String, title: String, maxLength: Int) -> String {
        guard !title.isEmpty else { return appName }
        let limit = max(maxLength, 1)
        var shown = title
        if title.count > limit {
            shown = String(title.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return appName.isEmpty ? shown : "\(appName) – \(shown)"
    }
}

/// Upstream's words for where a display is among all of them, for "Capture full screen" (`TrayMenu.cs`
/// `CreateFullscreenItem`): "top"/"bottom" when it touches only that edge of the space all displays span, then
/// "left"/"right" the same way.
public enum ScreenPosition {
    /// Frames in Quartz global coordinates (y grows downwards), like upstream's screen bounds.
    public static func words(for frame: CGRect, among frames: [CGRect]) -> [String] {
        guard frames.count > 1 else { return [] }
        let all = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        var words: [String] = []
        if frame.minY == all.minY && frame.maxY != all.maxY {
            words.append(String(localized: "top", comment: "Position of a display among all displays, after its name: Studio Display (top left)"))
        } else if frame.minY != all.minY && frame.maxY == all.maxY {
            words.append(String(localized: "bottom", comment: "Position of a display among all displays, after its name: Studio Display (top left)"))
        }
        if frame.minX == all.minX && frame.maxX != all.maxX {
            words.append(String(localized: "left", comment: "Position of a display among all displays, after its name: Studio Display (top left)"))
        } else if frame.minX != all.minX && frame.maxX == all.maxX {
            words.append(String(localized: "right", comment: "Position of a display among all displays, after its name: Studio Display (top left)"))
        }
        return words
    }

    /// "Studio Display (top left)", or just the name when no word applies.
    public static func label(name: String, frame: CGRect, among frames: [CGRect]) -> String {
        let words = words(for: frame, among: frames)
        return words.isEmpty ? name : "\(name) (\(words.joined(separator: " ")))"
    }
}

/// "Open last capture location" (upstream `TrayActions.OpenLastCaptureLocation`): the last saved file in Finder; when
/// it is gone its folder, else the output folder; nothing when neither exists.
public enum LastCaptureLocation: Equatable, Sendable {
    case selectFile(URL)
    case openFolder(URL)

    public static func resolve(lastSavedFile: String?, outputFolder: URL,
                               fileExists: (String) -> Bool, directoryExists: (String) -> Bool) -> LastCaptureLocation? {
        if let lastSavedFile, !lastSavedFile.isEmpty {
            let file = URL(fileURLWithPath: lastSavedFile)
            if fileExists(file.path) { return .selectFile(file) }
            let folder = URL(fileURLWithPath: file.deletingLastPathComponent().path, isDirectory: true)
            if directoryExists(folder.path) { return .openFolder(folder) }
        }
        return directoryExists(outputFolder.path) ? .openFolder(outputFolder) : nil
    }
}

/// Size and place of the window picture beside the window list (upstream `Greenshot.Base/Wpf/ThumbnailWindow.cs`).
public enum MenuBarThumbnailLayout {
    /// Upstream's thumbnails are 200 high.
    public static let maxHeight: CGFloat = 200
    public static let maxWidth: CGFloat = 360

    /// The window's size scaled to fit `maxWidth` × `maxHeight`, keeping its proportions; never larger than it is.
    public static func size(for windowSize: CGSize, maxWidth: CGFloat = maxWidth, maxHeight: CGFloat = maxHeight) -> CGSize {
        guard windowSize.width > 0, windowSize.height > 0 else { return .zero }
        let factor = min(maxWidth / windowSize.width, maxHeight / windowSize.height, 1)
        return CGSize(width: (windowSize.width * factor).rounded(), height: (windowSize.height * factor).rounded())
    }

    /// Where the picture goes, in AppKit screen coordinates (y up): beside the menu (right of it, else left), its middle
    /// at the mouse's height, inside `screen`; beside the mouse when the menu's frame is unknown.
    public static func frame(size: CGSize, menuFrame: CGRect?, mouse: CGPoint, screen: CGRect, gap: CGFloat = 6) -> CGRect {
        let anchor = menuFrame ?? CGRect(x: mouse.x - 12, y: mouse.y, width: 24, height: 0)
        var x = anchor.maxX + gap
        if x + size.width > screen.maxX {
            x = anchor.minX - gap - size.width
        }
        x = min(max(x, screen.minX), max(screen.maxX - size.width, screen.minX))
        var y = mouse.y - size.height / 2
        y = min(max(y, screen.minY), max(screen.maxY - size.height, screen.minY))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

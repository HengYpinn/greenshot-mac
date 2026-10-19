// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// What the menu bar icon's clicks and some of its menu items do (upstream `Greenshot/Shell/TrayActions.cs` and
/// `TrayIcon.OnClick`).
@MainActor
enum MenuBarActions {
    /// A click action of the menu bar icon. `showMenu` opens the icon's menu.
    static func perform(_ action: ClickAction, app: AppDelegate, showMenu: () -> Void) {
        switch action {
        case .doNothing: break
        case .openLastInFinder: openLastCaptureLocation(settings: app.settings)
        case .openLastInEditor: openLastCaptureInEditor(app: app)
        case .openSettings: app.showSettings(nil)
        case .showMenu: showMenu()
        case .captureRegion: app.capture.captureRegion(byAutomation: false)
        // Every screen, like upstream's `ScreenCaptureMode.FullScreen` for this action.
        case .captureScreen: app.capture.captureFullScreen(byAutomation: false)
        case .captureClipboard: captureClipboard(app: app)
        case .captureWindow: app.capture.captureWindowInteractively(byAutomation: false)
        case .openEmptyEditor: app.editors.openEmptyEditor()
        case .openFileInEditor: app.editors.chooseAndOpenFile()
        case .openClipboardInEditor: app.editors.openClipboard()
        }
    }

    /// The last saved file in Finder; when it is gone its folder, else the output folder (upstream
    /// `OpenLastCaptureLocation`). A beep when there is nothing to show.
    static func openLastCaptureLocation(settings: SettingsStore) {
        let s = settings.value
        let location = LastCaptureLocation.resolve(lastSavedFile: s.lastSavedFile, outputFolder: s.outputFolderURL,
                                                   fileExists: { exists($0, directory: false) },
                                                   directoryExists: { exists($0, directory: true) })
        switch location {
        case .selectFile(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openFolder(let url): NSWorkspace.shared.open(url)
        case nil: NSSound.beep()
        }
    }

    /// The last saved file in an editor (upstream `OpenLastCaptureInEditor`).
    static func openLastCaptureInEditor(app: AppDelegate) {
        guard let path = app.settings.value.lastSavedFile, exists(path, directory: false) else {
            NSSound.beep()
            return
        }
        app.editors.open(fileURL: URL(fileURLWithPath: path))
    }

    /// The image on the clipboard goes to the destinations like a capture (upstream `CaptureHelper.CaptureClipboard`).
    static func captureClipboard(app: AppDelegate) {
        if RecipeRuntime.shared?.interceptBuiltIn(.clipboard, destinations: app.settings.value.destinations) == true { return }
        guard let pasted = Clipboard.image() else {
            ErrorPresenter.show(message: String(localized: "There is no image on the clipboard"), detail: String(localized: "Copy an image first, then try again."))
            return
        }
        app.output.handle(Capture(image: pasted.image, scale: pasted.scale, title: "Clipboard"))
    }

    /// "Open Image from File…" of the menu (upstream `TrayActions.CaptureFile`): the chosen images go to the
    /// destinations like captures. When the editor is the only destination they open as files, so Save writes back.
    static func openFilesToDestinations(app: AppDelegate) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if RecipeRuntime.shared?.interceptBuiltIn(.file(url), destinations: app.settings.value.destinations) == true { continue }
            if app.settings.value.destinations == [.editor] {
                app.editors.open(fileURL: url)
                continue
            }
            guard let loaded = ImageLoader.load(url) else {
                ErrorPresenter.show(message: String(localized: "The image could not be opened"), detail: url.lastPathComponent)
                continue
            }
            app.output.handle(Capture(image: loaded.image, scale: loaded.scale, title: url.deletingPathExtension().lastPathComponent))
        }
    }

    private static func exists(_ path: String, directory: Bool) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue == directory
    }
}

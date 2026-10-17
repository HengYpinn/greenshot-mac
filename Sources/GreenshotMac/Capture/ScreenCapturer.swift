// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ScreenCaptureKit

/// A finished capture on its way to the destinations (upstream `ICapture` with its `CaptureDetails`).
struct Capture {
    var image: CGImage
    /// Pixels per point.
    var scale: CGFloat
    var title: String
    var date = Date()
    /// The text mode of the capture screen: the recognised text. A capture with text goes to the clipboard as text,
    /// not to the destinations; `image` is then the picture of the selected words.
    var text: String? = nil
}

/// A normal on-screen window of another app.
struct WindowInfo: Equatable {
    let id: CGWindowID
    /// Quartz global points.
    let frame: CGRect
    let title: String
    let appName: String
    let pid: pid_t
    /// The window level: 0 for normal windows, higher for palettes, panels and menus.
    var level = 0

    var displayTitle: String { title.isEmpty ? appName : title }
    var menuTitle: String { title.isEmpty ? appName : "\(appName) – \(title)" }
}

enum CaptureError: LocalizedError {
    case windowNotFound
    case nothingToCapture

    var errorDescription: String? {
        switch self {
        case .windowNotFound: return "The window is no longer on the screen."
        case .nothingToCapture: return "There was nothing on the screen to capture."
        }
    }
}

@MainActor
enum ScreenCapturer {
    /// The window levels the capture screen's window mode picks besides normal windows: floating palettes, panels,
    /// utility windows and open menus (upstream picks the innermost window, e.g. a panel or a toolbar; the windows
    /// inside an app's window would need the Accessibility permission). The menu bar, the Dock and the like aren't.
    static let pickableLevels: Set<Int> = Set([CGWindowLevelKey.floatingWindow, .tornOffMenuWindow, .modalPanelWindow,
                                               .utilityWindow, .popUpMenuWindow].map { Int(CGWindowLevelForKey($0)) })

    /// The normal windows of other apps that are on screen, front to back; `includingPanels` adds the windows of
    /// `pickableLevels`, except those covering a whole display (an invisible overlay would catch every move).
    static func onScreenWindows(includingPanels: Bool = false) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let displays = includingPanels ? activeDisplayBounds() : []
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 || (includingPanels && pickableLevels.contains(layer)),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 10, bounds.height >= 10,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  layer == 0 || !displays.contains(where: { bounds.contains($0) })
            else { return nil }
            return WindowInfo(id: number, frame: bounds,
                              title: info[kCGWindowName as String] as? String ?? "",
                              appName: info[kCGWindowOwnerName as String] as? String ?? "",
                              pid: pid, level: layer)
        }
    }

    /// The bounds of the displays, Quartz global points.
    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    /// The front window of the active app (or the front-most window when this app is active).
    static func frontWindow(in windows: [WindowInfo]) -> WindowInfo? {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return windows.first { $0.pid == frontPID } ?? windows.first
    }

    /// The title for a region: the normal window under its center, else the active app.
    static func title(for rect: CGRect, in windows: [WindowInfo]) -> String {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return windows.first { $0.level == 0 && $0.frame.contains(center) }?.displayTitle
            ?? NSWorkspace.shared.frontmostApplication?.localizedName
            ?? "Greenshot"
    }

    /// Takes a picture of every display, the "frozen" screen the capture overlay shows.
    static func freezeScreens(showsCursor: Bool) async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var screens: [FrozenScreen] = []
        for display in content.displays {
            screens.append(try await screenshot(of: display, showsCursor: showsCursor))
        }
        guard !screens.isEmpty else { throw CaptureError.nothingToCapture }
        return screens
    }

    /// Every display twice at the same moment, without and with the mouse pointer, so the capture screen can switch
    /// between them (M) after the picture was taken.
    static func freezeScreensWithAndWithoutPointer() async throws -> (plain: [FrozenScreen], pointer: [FrozenScreen]) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var plain: [FrozenScreen] = []
        var pointer: [FrozenScreen] = []
        for display in content.displays {
            async let without = screenshot(of: display, showsCursor: false)
            async let with = screenshot(of: display, showsCursor: true)
            let pair = try await (without, with)
            plain.append(pair.0)
            pointer.append(pair.1)
        }
        guard !plain.isEmpty else { throw CaptureError.nothingToCapture }
        return (plain, pointer)
    }

    private static func screenshot(of display: SCDisplay, showsCursor: Bool) async throws -> FrozenScreen {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return FrozenScreen(displayID: display.displayID, frame: CGDisplayBounds(display.displayID), scale: scale, image: image)
    }

    /// One window on its own, including the parts other windows cover.
    static func capture(window: WindowInfo, showsCursor: Bool, includeShadow: Bool) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = !includeShadow
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Capture(image: image, scale: scale, title: window.displayTitle)
    }
}

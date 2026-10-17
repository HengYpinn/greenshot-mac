// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The windows and displays for AI tools (upstream `AiToolIpcHandler.HandleListWindowsAsync`, `WindowHelper`): the
/// windows on the screen front to back (normal windows and panels, like the capture screen's window mode), with the
/// owner's names for the excluded applications.
enum AIToolsWindows {
    struct Listed {
        var id: CGWindowID
        /// Quartz global points, origin at the top left of the main display.
        var frame: CGRect
        var title: String
        var owner: String
        var pid: pid_t
        var layer: Int
        var bundleIdentifier: String?
        var executableName: String?

        /// The names an excluded application is matched by.
        var names: [String?] { [owner, bundleIdentifier, executableName] }
    }

    /// Palettes, panels, utility windows and open menus besides normal windows (`ScreenCapturer.pickableLevels`).
    static let pickableLevels: Set<Int> = Set([CGWindowLevelKey.floatingWindow, .tornOffMenuWindow, .modalPanelWindow,
                                               .utilityWindow, .popUpMenuWindow].map { Int(CGWindowLevelForKey($0)) })

    /// The windows on the screen, front to back. `allLevels`: also menus, the menu bar and other system windows (for
    /// blacking out a password manager's popup).
    static func windows(allLevels: Bool = false) -> [Listed] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var apps: [pid_t: (bundle: String?, executable: String?)] = [:]
        return list.compactMap { info -> Listed? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  allLevels || layer == 0 || pickableLevels.contains(layer),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  allLevels || (bounds.width >= 10 && bounds.height >= 10),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            if apps[pid] == nil {
                let app = NSRunningApplication(processIdentifier: pid)
                apps[pid] = (app?.bundleIdentifier, app?.executableURL?.lastPathComponent)
            }
            return Listed(id: number, frame: bounds, title: info[kCGWindowName as String] as? String ?? "",
                          owner: info[kCGWindowOwnerName as String] as? String ?? "", pid: pid, layer: layer,
                          bundleIdentifier: apps[pid]?.bundle, executableName: apps[pid]?.executable)
        }
    }

    /// The process of a window; nil when it isn't there any more (for `AIWindowRefs`).
    static func owner(of window: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], window) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == window }) else { return nil }
        return info[kCGWindowOwnerPID as String] as? pid_t
    }

    /// One window by number, also when it isn't on the screen.
    static func window(_ id: CGWindowID) -> Listed? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == id }),
              let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary
        let app = NSRunningApplication(processIdentifier: pid)
        return Listed(id: id, frame: boundsInfo.flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero,
                      title: info[kCGWindowName as String] as? String ?? "", owner: info[kCGWindowOwnerName as String] as? String ?? "",
                      pid: pid, layer: info[kCGWindowLayer as String] as? Int ?? 0, bundleIdentifier: app?.bundleIdentifier,
                      executableName: app?.executableURL?.lastPathComponent)
    }

    /// The displays: index, primary, bounds in global points and their scale (pixels per point).
    @MainActor
    static func displays() -> [JSONValue] {
        // The active displays; while they sleep (none active) the connected ones
        var ids = displayIDs(CGGetActiveDisplayList)
        if ids.isEmpty { ids = displayIDs(CGGetOnlineDisplayList) }
        let main = CGMainDisplayID()
        return ids.enumerated().map { index, id in
            let bounds = CGDisplayBounds(id)
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let display: JSONObject = ["index": .number(Double(index)), "primary": .bool(id == main),
                                       "x": .number(Double(bounds.minX)), "y": .number(Double(bounds.minY)),
                                       "width": .number(Double(bounds.width)), "height": .number(Double(bounds.height)),
                                       "scale": .number(Double(screen?.backingScaleFactor ?? 1))]
            return .object(display)
        }
    }

    private static func displayIDs(_ list: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard list(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard list(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// LIST_WINDOWS's reply: the windows with ids of this AI tool (the excluded applications' only counted) and the
    /// displays.
    @MainActor
    static func listReply(client: AIToolClient, refs: AIWindowRefs, excluded: [String]) -> IPCReply {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var activeShown = false
        var excludedCount = 0
        var windows: [JSONValue] = []
        for window in Self.windows() {
            if AIToolExclusion.isExcluded(names: window.names, excluded: excluded) {
                excludedCount += 1
                continue
            }
            let active = !activeShown && window.pid == frontPID && window.layer == 0
            if active { activeShown = true }
            let id = refs.register(scope: client.scopeKey, window: window.id, processID: window.pid)
            let entry: JSONObject = [
                "id": .string(id), "title": .string(window.title), "process": .string(window.owner),
                "bundle_id": window.bundleIdentifier.map(JSONValue.string) ?? .null, "pid": .number(Double(window.pid)),
                "x": .number(Double(window.frame.minX)), "y": .number(Double(window.frame.minY)),
                "width": .number(Double(window.frame.width)), "height": .number(Double(window.frame.height)),
                "layer": .number(Double(window.layer)), "minimized": .bool(false), "active": .bool(active),
            ]
            windows.append(.object(entry))
        }
        let displays = Self.displays()
        let extra: JSONObject = ["windows": .array(windows), "displays": .array(displays),
                                 "excluded_windows": .number(Double(excludedCount)),
                                 "id_lifetime_minutes": .number(AIWindowRefs.lifetime / 60)]
        return .ok("\(windows.count) windows, \(displays.count) displays.", extra: extra)
    }
}

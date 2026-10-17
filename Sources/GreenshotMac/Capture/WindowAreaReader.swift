// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import GreenshotCore

private let log = Log("Capture")

/// Reads the areas inside a window with the Accessibility API, once per window and capture screen (upstream
/// `Greenshot.Base/Capturing/WindowCaptureTool.cs` `FindAreasAsync`, which uses UI Automation). The capture screen
/// hit-tests the tree on every mouse move (`WindowAreas`).
///
/// The app's element is asked, not the system-wide one: that one would find the capture screen's own panels, which cover
/// every display. Each element costs one call into the other app, so the walk stops at `WindowAreas.maximumDepth`
/// levels, `maximumElements` elements or `timeLimit` seconds; a hanging app waits at most `messagingTimeout` per call.
///
/// Browsers show their web content to the Accessibility API only when asked: Chromium and Electron apps with
/// `AXManualAccessibility`, others with `AXEnhancedUserInterface` (which VoiceOver sets, and which slows window
/// animations of some apps). Both are set back when the capture screen closes (`finish()`).
final class WindowAreaReader: @unchecked Sendable {
    static let maximumElements = 2_000
    static let timeLimit: TimeInterval = 2
    static let messagingTimeout: Float = 1
    /// How long a browser gets to build its tree after it was asked to, and how often it is read meanwhile.
    static let webContentWait: TimeInterval = 2
    static let webContentRetry: TimeInterval = 0.3

    private static let manualAccessibility = "AXManualAccessibility" as CFString
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private let queue = DispatchQueue(label: "org.greenshot.mac.window-areas", qos: .userInitiated)
    private let lock = NSLock()
    /// Raised by `cancel()`: a running read stops at its next element.
    private var generation = 0
    // Only on `queue`:
    private var preparedApps: Set<pid_t> = []
    /// The attributes this reader changed, with the value to put back.
    private var changed: [(pid: pid_t, attribute: CFString, previous: Bool)] = []

    /// Reads the areas of `window` in the background; `completion` gets the tree on the main thread, nil when the app
    /// has none to tell, and is not called when the read was cancelled. `scale` is the display's pixels per point, for
    /// the minimum area size.
    func read(_ window: WindowInfo, scale: CGFloat, completion: @escaping @MainActor (WindowArea?) -> Void) {
        let token = lock.withLock { () -> Int in
            generation += 1
            return generation
        }
        queue.async { [self] in
            let start = Date()
            let tree = readTree(of: window, scale: scale, token: token)
            guard !isCancelled(token) else { return }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            log.debug("Areas of window \(window.id) (\(window.appName)) in \(elapsed) ms: \(tree.map { "\($0.count)" } ?? "none")")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(tree) }
            }
        }
    }

    /// Stops the read that is running (the mouse went to another window).
    func cancel() {
        lock.withLock { generation += 1 }
    }

    /// The capture screen closed: stop reading and put back what was changed in the apps.
    func finish() {
        cancel()
        queue.async { [self] in
            for change in changed.reversed() {
                let app = AXUIElementCreateApplication(change.pid)
                AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
                AXUIElementSetAttributeValue(app, change.attribute, (change.previous ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
            }
            changed.removeAll()
            preparedApps.removeAll()
        }
    }

    private func isCancelled(_ token: Int) -> Bool {
        lock.withLock { generation != token }
    }

    // MARK: Reading (on `queue`)

    private func readTree(of window: WindowInfo, scale: CGFloat, token: Int) -> WindowArea? {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        let askedForWebContent = prepare(app, pid: window.pid)
        guard let element = axWindow(of: app, matching: window) else { return nil }
        var tree = readOnce(element, scale: scale, token: token)
        // A browser asked a moment ago, or one that shows nothing yet: wait for its web content.
        var enhanced = false
        let deadline = Date().addingTimeInterval(Self.webContentWait)
        while let current = tree, current.hasEmptyWebArea, Date() < deadline, !isCancelled(token) {
            if !enhanced && !askedForWebContent {
                enhanced = true
                set(Self.enhancedUserInterface, on: app, pid: window.pid)
            }
            Thread.sleep(forTimeInterval: Self.webContentRetry)
            tree = readOnce(element, scale: scale, token: token)
        }
        return tree.map { WindowAreas.pruned($0, scale: scale) }
    }

    /// Asks a Chromium or Electron app for its web content, once per app and capture screen; true when it said yes.
    private func prepare(_ app: AXUIElement, pid: pid_t) -> Bool {
        guard !preparedApps.contains(pid) else { return false }
        preparedApps.insert(pid)
        return set(Self.manualAccessibility, on: app, pid: pid)
    }

    /// Turns `attribute` on and remembers its value before; false when the app doesn't have it.
    @discardableResult
    private func set(_ attribute: CFString, on app: AXUIElement, pid: pid_t) -> Bool {
        var value: CFTypeRef?
        let previous = AXUIElementCopyAttributeValue(app, attribute, &value) == .success && (value as? Bool) == true
        guard !previous else { return false }
        guard AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) == .success else { return false }
        changed.append((pid, attribute, previous))
        log.debug("Set \(attribute) on process \(pid) for the areas of its windows")
        return true
    }

    /// The app's window with the frame of `window` (the title decides between two of the same size).
    private func axWindow(of app: AXUIElement, matching window: WindowInfo) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AnyObject] else { return nil }
        let candidates = windows.compactMap(Self.element).filter { element in
            guard let frame = Self.frame(of: element) else { return false }
            return abs(frame.minX - window.frame.minX) <= 2 && abs(frame.minY - window.frame.minY) <= 2
                && abs(frame.width - window.frame.width) <= 2 && abs(frame.height - window.frame.height) <= 2
        }
        guard candidates.count > 1 else { return candidates.first }
        return candidates.first { Self.string(kAXTitleAttribute, of: $0) == window.title } ?? candidates.first
    }

    private struct Budget {
        var elements = 0
        let deadline = Date().addingTimeInterval(WindowAreaReader.timeLimit)
        var isSpent: Bool { elements >= WindowAreaReader.maximumElements || Date() >= deadline }
    }

    private func readOnce(_ window: AXUIElement, scale: CGFloat, token: Int) -> WindowArea? {
        var budget = Budget()
        // The window is level 0, its areas count from 1, as in `WindowAreas.pruned`.
        return read(window, parent: nil, depth: -1, scale: scale, token: token, budget: &budget)
    }

    private static let attributes = [kAXRoleAttribute, kAXRoleDescriptionAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                                     kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray

    /// One element and what is inside it, read with one call per element; nil for a small or unreadable one.
    private func read(_ element: AXUIElement, parent: CGRect?, depth: Int, scale: CGFloat, token: Int,
                      budget: inout Budget) -> WindowArea? {
        guard !budget.isSpent, !isCancelled(token) else { return nil }
        budget.elements += 1
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, Self.attributes, AXCopyMultipleAttributeOptions(rawValue: 0),
                                                     &values) == .success,
              let list = values as? [AnyObject], list.count == 7,
              let position = Self.point(list[4]), let size = Self.size(list[5]) else { return nil }
        let frame = CGRect(origin: position, size: size)
        // The window itself always; inside it only areas big enough (what is inside a small area is smaller still).
        guard parent == nil || WindowAreas.isLargeEnough(frame, scale: scale) else { return nil }
        let level = WindowAreas.countsAsLevel(frame, parent: parent) ? depth + 1 : depth
        let role = list[0] as? String ?? ""
        let title = (list[2] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (list[3] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let kind = (list[1] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? role
        var area = WindowArea(frame: frame, role: role, name: title.map { "\(kind) “\($0)”" } ?? kind)
        if level < WindowAreas.maximumDepth, let children = list[6] as? [AnyObject] {
            area.children = children.compactMap(Self.element).compactMap {
                read($0, parent: frame, depth: level, scale: scale, token: token, budget: &budget)
            }
        }
        return area
    }

    // MARK: Values

    private static func element(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ value: AnyObject) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func point(_ value: AnyObject) -> CGPoint? {
        guard let value = axValue(value), AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(_ value: AnyObject) -> CGSize? {
        guard let value = axValue(value), AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, let origin = point(position as AnyObject), let extent = self.size(size as AnyObject)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

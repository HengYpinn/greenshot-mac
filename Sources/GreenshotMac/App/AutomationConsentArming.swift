// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The arming of a consent question's buttons (the AI tools' consent panel, the command line capture question): they
/// react only a second after the question was last shown unchanged. A click before that (the user was clicking somewhere
/// else) starts the second again, and so does the question being covered or uncovered. A click on "Allow" counts only
/// when no window of another program lies over the question (`ConsentClickGuard`, security review SM-M2).
@MainActor
final class ConsentArming: NSObject {
    static let delay: TimeInterval = 1

    private weak var window: NSWindow?
    private let buttons: [NSButton]
    private var timer: Timer?
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private(set) var isArmed = false
    private let log = Log("Automation")

    init(window: NSWindow, buttons: [NSButton]) {
        self.window = window
        self.buttons = buttons
        super.init()
    }

    /// Disarmed now, armed after the delay; clicks and occlusion changes start the delay again.
    func start() {
        disarm()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, !self.isArmed, event.window === self.window { self.disarm() }
            }
            return event
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.disarm() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Buttons off, and on again after the delay.
    func disarm() {
        isArmed = false
        buttons.forEach { $0.isEnabled = false }
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.arm() }
        }
        // Common modes: also while a modal alert runs
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func arm() {
        isArmed = true
        buttons.forEach { $0.isEnabled = true }
    }

    /// The "Allow" click: true when it counts. A covered question disarms itself instead.
    func confirmAllow() -> Bool {
        guard isArmed, let window else { return false }
        if Self.isCovered(window) {
            log.warn("[SECURITY] A click on Allow was ignored: another program's window lies over the question.")
            disarm()
            return false
        }
        return true
    }

    /// Whether a window of another process lies over `window` right now.
    static func isCovered(_ window: NSWindow) -> Bool {
        let number = CGWindowID(window.windowNumber)
        guard number > 0,
              let own = (CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]])?.first,
              let ownBounds = own[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: ownBounds) else { return false }
        let above = (CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], number) as? [[String: Any]] ?? []).compactMap { info -> ConsentClickGuard.WindowAbove? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return ConsentClickGuard.WindowAbove(ownerPID: pid, frame: rect, alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
        return ConsentClickGuard.isCovered(frame, by: above, ownPID: ProcessInfo.processInfo.processIdentifier)
    }
}

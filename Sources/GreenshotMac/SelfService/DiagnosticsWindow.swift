// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The windows of the diagnostics and the welcome (Self-Service, log viewer, bug report, welcome, About) that are
/// open: while one is, the app gets its Dock icon like with an editor (`AppDelegate.updateDockIcon`).
@MainActor
enum AuxiliaryWindows {
    static var onChange: (() -> Void)?
    private static var open: Set<ObjectIdentifier> = []

    static var anyOpen: Bool { !open.isEmpty }

    static func opened(_ window: NSWindow) {
        if open.insert(ObjectIdentifier(window)).inserted { onChange?() }
    }

    static func closed(_ window: NSWindow) {
        if open.remove(ObjectIdentifier(window)) != nil { onChange?() }
    }
}

/// A window whose keys reach `onKey` when nothing inside used them: upstream's windows react to Esc, F5 and letters
/// (`OnWindowKeyDown`). Text fields keep the letters typed into them, so a letter key only arrives here when no text
/// field has the focus. Esc closes the window unless `onKey` takes it.
final class KeyHandlingWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        if Int(event.keyCode) == kVK_Escape {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    /// The letter of a key without modifiers (except Shift), lowercased; nil for other keys or with ⌘, ⌃ or ⌥.
    static func plainLetter(_ event: NSEvent) -> String? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else { return nil }
        return characters
    }
}

/// The controller of one diagnostics window: a SwiftUI view in a `KeyHandlingWindow`, which comes to the Space the user
/// is on and counts for the Dock icon while it is open. Unlike Settings it stays when another app is clicked, so it
/// can be read next to System Settings.
@MainActor
class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    init<Content: View>(title: String, content: Content, size: NSSize, resizable: Bool, autosaveName: String? = nil) {
        let hosting = NSHostingController(rootView: content)
        let window = KeyHandlingWindow(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable],
                                       backing: .buffered, defer: true)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
        if autosaveName == nil || window.frame.origin == .zero { window.center() }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var keyWindow: KeyHandlingWindow? { window as? KeyHandlingWindow }

    /// Shows the window in front, on the user's Space.
    func present() {
        guard let window else { return }
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        AuxiliaryWindows.opened(window)
    }

    var isOpen: Bool { window?.isVisible == true || window?.isMiniaturized == true }

    func windowWillClose(_ notification: Notification) {
        if let window { AuxiliaryWindows.closed(window) }
        didClose()
    }

    /// For subclasses: the window was closed.
    func didClose() {}

    func windowDidBecomeKey(_ notification: Notification) {
        didBecomeKey()
    }

    /// For subclasses: the window became the key window (e.g. back from System Settings).
    func didBecomeKey() {}
}

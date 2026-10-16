// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// A button that records a global shortcut: click it, then type the keys. ⌫ clears, ⎋ cancels.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = { combo = $0 }
        button.combo = combo
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = { combo = $0 }
        button.combo = combo
    }
}

final class ShortcutRecorderButton: NSButton {
    /// While recording, the global hotkeys are off so the keys reach the button.
    static let recordingDidBegin = Notification.Name("ShortcutRecordingDidBegin")
    static let recordingDidEnd = Notification.Name("ShortcutRecordingDidEnd")

    var combo: KeyCombo? {
        didSet { updateTitle() }
    }
    var onChange: ((KeyCombo?) -> Void)?
    private var windowObservers: [NSObjectProtocol] = []

    private var recording = false {
        didSet {
            guard oldValue != recording else { return }
            updateTitle()
            NotificationCenter.default.post(name: recording ? Self.recordingDidBegin : Self.recordingDidEnd, object: self)
        }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(toggleRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var acceptsFirstResponder: Bool { true }

    // Recording turns the global hotkeys off, so it has to end however the user leaves: closing the window,
    // switching to another app or tab, not only by typing a key.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { recording = false }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        guard let window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recording = false }
            })
        }
    }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let candidate = KeyCombo(event: event)
        switch Int(event.keyCode) {
        case kVK_Escape where candidate.modifiers == 0:
            recording = false
            return
        case kVK_Delete where candidate.modifiers == 0, kVK_ForwardDelete where candidate.modifiers == 0:
            combo = nil
            onChange?(nil)
            recording = false
            return
        default:
            break
        }
        guard candidate.isValidGlobalShortcut else {
            NSSound.beep()
            return
        }
        combo = candidate
        onChange?(candidate)
        recording = false
    }

    private func updateTitle() {
        title = recording ? "Type the shortcut…" : (combo?.displayString ?? "None")
    }
}

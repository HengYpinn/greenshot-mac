// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// A button that records a global shortcut: click it, then type the keys. ⌫ clears, ⎋ cancels. The + next to it adds a
/// step (a key pressed after the others, like the C of "⌃⌥⌘K, C"), the arrow goes back to one step. The Mac's inline
/// form of upstream's "Configure Hotkey" dialog (`HotkeyEditorView.xaml`): a key that can't be used is explained in
/// `problem` instead of only beeping.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    @Binding var problem: String?

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        update(view)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        update(view)
    }

    private func update(_ view: ShortcutRecorderView) {
        view.button.onChange = { combo = $0 }
        view.button.onProblem = { problem = $0 }
        view.button.combo = combo
    }
}

/// The recording button with its + (add a step) and back-to-one-step buttons.
final class ShortcutRecorderView: NSStackView {
    let button = ShortcutRecorderButton()
    private let addStep = NSButton()
    private let reset = NSButton()

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 4
        for (control, symbol, tip) in [(addStep, "plus.circle", "Add a step: a key to press after the others, like the C of ⌃⌥⌘K, C"),
                                       (reset, "arrow.uturn.backward.circle", "Back to one step")] {
            control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            control.isBordered = false
            control.imagePosition = .imageOnly
            control.toolTip = tip
            control.target = self
            control.setAccessibilityLabel(tip)
        }
        addStep.action = #selector(addStepClicked)
        reset.action = #selector(resetClicked)
        addArrangedSubview(button)
        addArrangedSubview(addStep)
        addArrangedSubview(reset)
        button.onLayoutChange = { [weak self] in self?.updateButtons() }
        updateButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func updateButtons() {
        let combo = button.combo
        addStep.isEnabled = combo != nil && (combo?.chords.count ?? 0) < KeyCombo.maximumSteps
        reset.isHidden = combo?.isSequence != true
    }

    @objc private func addStepClicked() {
        button.startRecording(appending: true)
    }

    @objc private func resetClicked() {
        guard var combo = button.combo else { return }
        combo.followingChords = []
        button.combo = combo
        button.onChange?(combo)
        button.onProblem?(nil)
    }
}

final class ShortcutRecorderButton: NSButton {
    /// While recording, the global hotkeys are off so the keys reach the button.
    static let recordingDidBegin = Notification.Name("ShortcutRecordingDidBegin")
    static let recordingDidEnd = Notification.Name("ShortcutRecordingDidEnd")

    var combo: KeyCombo? {
        didSet {
            updateTitle()
            onLayoutChange?()
        }
    }
    var onChange: ((KeyCombo?) -> Void)?
    /// Why the typed keys can't be a hotkey, nil when they can.
    var onProblem: ((String?) -> Void)?
    var onLayoutChange: (() -> Void)?
    private var windowObservers: [NSObjectProtocol] = []
    /// The typed key becomes the next step instead of the whole hotkey.
    private var appending = false

    private var recording = false {
        didSet {
            guard oldValue != recording else { return }
            if !recording { appending = false }
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
        if recording {
            recording = false
        } else {
            startRecording(appending: false)
        }
    }

    /// Starts recording the whole hotkey, or (`appending`) the next step of it.
    func startRecording(appending: Bool) {
        self.appending = appending && combo != nil
        recording = true
        window?.makeFirstResponder(self)
        updateTitle()
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
        let typed = KeyCombo(event: event).firstChord
        switch Int(event.keyCode) {
        case kVK_Escape where typed.modifiers == 0:
            onProblem?(nil)
            recording = false
            return
        case kVK_Delete where typed.modifiers == 0, kVK_ForwardDelete where typed.modifiers == 0:
            combo = nil
            onChange?(nil)
            onProblem?(nil)
            recording = false
            return
        default:
            break
        }
        let candidate = appending ? combo.flatMap { KeyCombo(chords: $0.chords + [typed]) } : KeyCombo(chords: [typed])
        guard let candidate else { return }
        if let problem = candidate.validationProblem {
            NSSound.beep()
            onProblem?(problem)
            return
        }
        combo = candidate
        onChange?(candidate)
        onProblem?(nil)
        recording = false
    }

    private func updateTitle() {
        if recording {
            title = appending ? "\(combo?.displayString ?? ""), …" : "Type the shortcut…"
        } else {
            title = combo?.displayString ?? "None"
        }
    }
}

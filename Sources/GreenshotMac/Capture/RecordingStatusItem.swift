// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// What the recording indicator shows.
enum RecordingIndicatorState: Equatable {
    /// Seconds until the recording starts.
    case countdown(Int)
    /// The stream and the file are being set up.
    case starting
    case recording(TimeInterval)
    case paused(TimeInterval)
    /// The file is being finished.
    case saving
}

/// What the recording's menu items do.
struct RecordingActions {
    var stop: () -> Void = {}
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var discard: () -> Void = {}
    var cancelCountdown: () -> Void = {}
}

/// The menu items of a recording that runs, for the menu bar menu and the indicator's menu.
@MainActor
enum RecordingMenus {
    static func items(for state: RecordingIndicatorState, hotkey: KeyCombo?, actions: RecordingActions) -> [NSMenuItem] {
        switch state {
        case .countdown:
            return [item("Cancel Recording", hotkey, actions.cancelCountdown)]
        case .starting:
            // Done as soon as the recording runs.
            return [item("Stop Recording", hotkey, actions.stop), item("Discard Recording", nil, actions.discard)]
        case .recording(let elapsed), .paused(let elapsed):
            let paused: Bool
            if case .paused = state { paused = true } else { paused = false }
            return [item("Stop Recording (\(RecordingText.elapsed(elapsed)))", hotkey, actions.stop),
                    paused ? item("Resume Recording", nil, actions.resume) : item("Pause Recording", nil, actions.pause),
                    item("Discard Recording", nil, actions.discard)]
        case .saving:
            let saving = NSMenuItem(title: "Saving the Recording…", action: nil, keyEquivalent: "")
            saving.isEnabled = false
            return [saving]
        }
    }

    /// A menu item that shows its global hotkey, like the menu bar menu's capture items.
    static func item(_ title: String, _ combo: KeyCombo?, _ action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, handler: action)
        if let combo, let key = combo.menuKeyEquivalent {
            entry.keyEquivalent = key
            entry.keyEquivalentModifierMask = combo.modifierFlags
        }
        return entry
    }
}

/// The recording indicator in the menu bar, beside Greenshot's icon while a recording counts down, runs or is saved: a
/// red dot and the recorded time. A click stops the recording (or cancels the countdown), like macOS's own stop button;
/// a right-click or ⌃-click shows the menu with pause, resume and discard.
@MainActor
final class RecordingStatusItem: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: RecordingActions
    private let hotkey: () -> KeyCombo?
    var state: RecordingIndicatorState {
        didSet { if state != oldValue { update() } }
    }

    init(state: RecordingIndicatorState, hotkey: @escaping () -> KeyCombo?, actions: RecordingActions) {
        self.state = state
        self.actions = actions
        self.hotkey = hotkey
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        update()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func update() {
        guard let button = statusItem.button else { return }
        Self.configure(button, state: state)
    }

    /// The button's picture, time and help text (also for the snapshots).
    static func configure(_ button: NSButton, state: RecordingIndicatorState) {
        let symbol: String
        let color: NSColor
        let text: String
        let help: String
        switch state {
        case .countdown(let seconds):
            symbol = "timer"
            color = .systemOrange
            text = "\(seconds)"
            help = "The recording starts in \(seconds) s. Click to cancel."
        case .starting:
            symbol = "record.circle"
            color = .systemRed
            text = "Starting…"
            help = "The recording is starting. Click to stop it as soon as it runs."
        case .recording(let elapsed):
            symbol = "record.circle.fill"
            color = .systemRed
            text = RecordingText.elapsed(elapsed)
            help = "Recording. Click to stop; ⌃-click to pause or discard."
        case .paused(let elapsed):
            symbol = "pause.circle.fill"
            color = .systemOrange
            text = RecordingText.elapsed(elapsed)
            help = "The recording is paused. Click to stop; ⌃-click to go on or discard."
        case .saving:
            symbol = "arrow.down.circle"
            color = .secondaryLabelColor
            text = "Saving…"
            help = "The recording is being saved."
        }
        // A filled symbol: a white mark (dot, pause bars) on the coloured circle.
        let colors: [NSColor] = symbol.hasSuffix(".fill") ? [.white, color] : [color]
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Recording")?.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        button.image = image
        button.imagePosition = .imageLeading
        // A plain title, so the menu bar draws it in its own colour (light or dark).
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = " " + text
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let menuClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if menuClick {
            showMenu()
            return
        }
        switch state {
        case .countdown: actions.cancelCountdown()
        case .starting, .recording, .paused: actions.stop()
        case .saving: break
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        RecordingMenus.items(for: state, hotkey: hotkey(), actions: actions).forEach(menu.addItem)
        button.highlight(true)
        let below = NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY + 5 : -5)
        menu.popUp(positioning: nil, at: below, in: button)
        button.highlight(false)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

private let hotKeySignature: OSType = 0x4753_4D43 // "GSMC"

/// Global hotkeys through Carbon's `RegisterEventHotKey` (upstream `HotkeyManager`). Unlike an event tap this
/// needs no Accessibility permission.
///
/// A hotkey can have several steps ("⌃⌥⌘K, C", upstream `HotkeySequence`). Carbon only reports registered keys, so
/// the first step of every hotkey is registered all the time, and while a hotkey is half typed the keys that may come
/// next (and Esc) are registered too, for at most `HotkeySequenceMatcher.chordTimeout` seconds.
@MainActor
final class HotkeyManager {
    private struct Registration {
        let ref: EventHotKeyRef
        let chord: KeyChord
    }

    /// The first steps, registered while the hotkeys are on.
    private var registrations: [UInt32: Registration] = [:]
    /// The possible next steps of a half typed hotkey.
    private var pendingRegistrations: [UInt32: Registration] = [:]
    private var matcher = HotkeySequenceMatcher(hotkeys: [])
    private var actions: [() -> Void] = []
    private var timeout: Timer?
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            // Carbon delivers hotkey events on the main thread; run the action after the event is handled.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { manager.pressed(id) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Registers `hotkeys` with their actions, replacing the ones before. Returns the indices of the hotkeys macOS
    /// refused (another app may own their first step).
    @discardableResult
    func register(_ hotkeys: [KeyCombo], actions: [() -> Void]) -> [Int] {
        unregisterAll()
        matcher = HotkeySequenceMatcher(hotkeys: hotkeys)
        self.actions = actions
        var refused: Set<KeyChord> = []
        for chord in matcher.firstChords {
            if let registration = carbonRegister(chord) {
                registrations[registration.id] = registration.value
            } else {
                refused.insert(chord)
            }
        }
        return hotkeys.indices.filter { refused.contains(hotkeys[$0].firstChord) }
    }

    func unregisterAll() {
        endPending()
        registrations.values.forEach { UnregisterEventHotKey($0.ref) }
        registrations.removeAll()
        matcher = HotkeySequenceMatcher(hotkeys: [])
        actions = []
    }

    /// Registers the hotkeys from the settings, replacing the ones registered before, and tells the user about those
    /// macOS refused (upstream `HotkeyHelper.RegisterHotkeys`).
    func registerAll(_ hotkeys: HotkeySettings, capture: CaptureCoordinator, editors: EditorManager) {
        var combos: [KeyCombo] = []
        var names: [String] = []
        var actions: [() -> Void] = []
        func bind(_ combo: KeyCombo?, _ name: String, _ action: @escaping () -> Void) {
            guard let combo else { return }
            combos.append(combo)
            names.append(name)
            actions.append(action)
        }
        bind(hotkeys.region, "Capture region") { [weak capture] in capture?.captureRegion() }
        bind(hotkeys.window, "Capture window") { [weak capture] in capture?.captureWindowFromHotkey() }
        bind(hotkeys.fullScreen, "Capture full screen") { [weak capture] in capture?.captureFullScreenFromHotkey() }
        bind(hotkeys.lastRegion, "Capture last region") { [weak capture] in capture?.captureLastRegion() }
        bind(hotkeys.text, "Capture text") { [weak capture] in capture?.captureText() }
        bind(hotkeys.clipboard, "Open clipboard") { [weak editors] in editors?.openClipboard() }
        let failed = register(combos, actions: actions).map { "\(names[$0]): \(combos[$0].displayString)" }
        if !failed.isEmpty {
            ErrorPresenter.show(message: "Some hotkeys could not be registered",
                                detail: failed.joined(separator: "\n") + "\n\nAnother app may use them. Choose others in Settings › General.")
        }
    }

    // MARK: Keys

    private func pressed(_ id: UInt32) {
        guard let chord = (registrations[id] ?? pendingRegistrations[id])?.chord else { return }
        switch matcher.feed(chord, at: Date()) {
        case .completed(let index):
            endPending()
            if actions.indices.contains(index) { actions[index]() }
        case .pending:
            beginPending()
        case .cancelled, .ignored:
            endPending()
        }
    }

    /// Registers the keys that may come next, for the time allowed between two steps. A key that is already registered
    /// (the first step of another hotkey) still reaches the matcher through its own registration.
    private func beginPending() {
        endPendingRegistrations()
        for chord in matcher.pendingChords where !registrations.values.contains(where: { $0.chord == chord }) {
            if let registration = carbonRegister(chord) { pendingRegistrations[registration.id] = registration.value }
        }
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: HotkeySequenceMatcher.chordTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPending() }
        }
    }

    private func endPending() {
        matcher.reset()
        timeout?.invalidate()
        timeout = nil
        endPendingRegistrations()
    }

    private func endPendingRegistrations() {
        pendingRegistrations.values.forEach { UnregisterEventHotKey($0.ref) }
        pendingRegistrations.removeAll()
    }

    private func carbonRegister(_ chord: KeyChord) -> (id: UInt32, value: Registration)? {
        var ref: EventHotKeyRef?
        let id = nextID
        nextID &+= 1
        let status = RegisterEventHotKey(chord.keyCode, chord.modifiers, EventHotKeyID(signature: hotKeySignature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        return (id, Registration(ref: ref, chord: chord))
    }
}

extension KeyCombo {
    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: KeyCombo.carbonModifiers(from: event.modifierFlags))
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= control }
        if flags.contains(.option) { result |= option }
        if flags.contains(.shift) { result |= shift }
        if flags.contains(.command) { result |= command }
        return result
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & KeyCombo.control != 0 { flags.insert(.control) }
        if modifiers & KeyCombo.option != 0 { flags.insert(.option) }
        if modifiers & KeyCombo.shift != 0 { flags.insert(.shift) }
        if modifiers & KeyCombo.command != 0 { flags.insert(.command) }
        return flags
    }

    /// The key equivalent to show the shortcut in a menu, when the key can be shown there. A hotkey of several steps
    /// has none: a menu can only show one.
    var menuKeyEquivalent: String? {
        guard !isSequence else { return nil }
        let name = KeyCombo.keyName(for: keyCode)
        if name.count == 1, let char = name.lowercased().first, char.isLetter || char.isNumber || char.isPunctuation {
            return String(char)
        }
        if name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...20).contains(number),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
            return String(Character(scalar))
        }
        return nil
    }
}

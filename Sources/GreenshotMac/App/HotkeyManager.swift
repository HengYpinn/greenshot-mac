// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

private let hotKeySignature: OSType = 0x4753_4D43 // "GSMC"

/// Global hotkeys through Carbon's `RegisterEventHotKey` (upstream `HotkeyManager`). Unlike an event tap this
/// needs no Accessibility permission.
@MainActor
final class HotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
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
                MainActor.assumeIsolated { manager.actions[id]?() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Returns false when macOS refused the combination (another app may own it).
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotKeySignature, id: nextID)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        actions[nextID] = action
        nextID += 1
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    /// Registers the hotkeys from the settings, replacing the ones registered before, and tells the user about those
    /// macOS refused.
    func registerAll(_ hotkeys: HotkeySettings, capture: CaptureCoordinator, editors: EditorManager) {
        unregisterAll()
        var failed: [String] = []
        func bind(_ combo: KeyCombo?, _ name: String, _ action: @escaping () -> Void) {
            guard let combo else { return }
            if !register(combo, action: action) { failed.append("\(name): \(combo.displayString)") }
        }
        bind(hotkeys.region, "Capture region") { [weak capture] in capture?.captureRegion() }
        bind(hotkeys.window, "Capture window") { [weak capture] in capture?.captureWindowFromHotkey() }
        bind(hotkeys.fullScreen, "Capture full screen") { [weak capture] in capture?.captureFullScreenFromHotkey() }
        bind(hotkeys.lastRegion, "Capture last region") { [weak capture] in capture?.captureLastRegion() }
        bind(hotkeys.clipboard, "Open clipboard") { [weak editors] in editors?.openClipboard() }
        if !failed.isEmpty {
            ErrorPresenter.show(message: "Some hotkeys could not be registered",
                                detail: failed.joined(separator: "\n") + "\n\nAnother app may use them. Choose others in Settings › General.")
        }
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

    /// The key equivalent to show the shortcut in a menu, when the key can be shown there.
    var menuKeyEquivalent: String? {
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

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

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
}

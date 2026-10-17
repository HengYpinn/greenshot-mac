// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

private let log = Log("Hotkeys")

/// A keyboard event tap for the hotkeys that need the left or the right key of a modifier (upstream's keyboard hook,
/// `Greenshot.Base/Core/HotkeyManager.cs`): Carbon's `RegisterEventHotKey` can't tell the keys apart, a tap sees the
/// device flags of every key event. Only those hotkeys use it; the others stay on Carbon, which needs no permission.
///
/// With Accessibility the tap filters (`.active`): a hotkey's keys don't reach the app in front, as with Carbon. With
/// only Input Monitoring it can just listen (`.listenOnly`): the hotkey works, but the app in front gets the keys too.
@MainActor
final class HotkeyEventTap {
    enum Mode: Equatable {
        case active
        case listenOnly
    }

    /// The best tap the permissions allow, nil without either.
    static var availableMode: Mode? {
        if Permissions.hasAccessibility { return .active }
        if Permissions.canListenToKeys { return .listenOnly }
        return nil
    }

    let mode: Mode
    /// A key was pressed: its key and Carbon modifiers, and the event's device flags. True when it belongs to a hotkey,
    /// so an active tap keeps it from the app in front.
    private let handler: (KeyChord, UInt64) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// The key of the last swallowed press: its repeats are swallowed too.
    private var swallowedKey: Int64?

    /// Starts the tap; nil when macOS refuses it (no permission after all).
    init?(mode: Mode, handler: @escaping (KeyChord, UInt64) -> Bool) {
        self.mode = mode
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: mode == .active ? .defaultTap : .listenOnly, eventsOfInterest: mask,
                                           callback: { _, type, event, userInfo in
                                               guard let userInfo else { return Unmanaged.passUnretained(event) }
                                               let tap = Unmanaged<HotkeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                                               // The tap's run loop source is on the main run loop.
                                               return MainActor.assumeIsolated { tap.handle(type, event) }
                                           },
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.warn("The keyboard event tap for left/right hotkeys could not be started")
            return nil
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: port, enable: true)
        log.info("Keyboard event tap started (\(mode == .active ? "filtering" : "listening only")) for left/right hotkeys")
    }

    /// Stops the tap; it must be called before the tap is released.
    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off; turn it on again.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return swallows(keyCode == swallowedKey) ? nil : Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            let chord = KeyChord(keyCode: UInt32(keyCode), modifiers: Self.carbonModifiers(flags))
            let used = handler(chord, flags.rawValue)
            swallowedKey = used ? keyCode : nil
            return swallows(used) ? nil : Unmanaged.passUnretained(event)
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == swallowedKey else { return Unmanaged.passUnretained(event) }
            swallowedKey = nil
            return swallows(true) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func swallows(_ used: Bool) -> Bool { used && mode == .active }

    static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskControl) { result |= KeyCombo.control }
        if flags.contains(.maskAlternate) { result |= KeyCombo.option }
        if flags.contains(.maskShift) { result |= KeyCombo.shift }
        if flags.contains(.maskCommand) { result |= KeyCombo.command }
        return result
    }
}

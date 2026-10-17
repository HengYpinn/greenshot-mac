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
///
/// A filtering tap holds up every key press on the Mac until it answers, so it runs on a thread of its own, never
/// behind the main thread (an export of a big image, saving at quit): it matches the keys there and goes to the main
/// thread only for a hotkey that is complete (`fired`).
final class HotkeyEventTap: @unchecked Sendable {
    enum Mode: Equatable, Sendable {
        case active
        case listenOnly
    }

    /// The best tap the permissions allow, nil without either.
    @MainActor
    static var availableMode: Mode? {
        if Permissions.hasAccessibility { return .active }
        if Permissions.canListenToKeys { return .listenOnly }
        return nil
    }

    let mode: Mode
    /// The hotkey with this index (of those given) was typed; called on the tap's thread.
    private let fired: (Int) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    // Only on the tap's thread:
    private var matcher: HotkeySequenceMatcher
    /// The key of the last swallowed press: its repeats and its release are swallowed too.
    private var swallowedKey: Int64?
    /// The tap thread's run loop, set before `init` returns.
    private var runLoop: CFRunLoop?

    /// Starts the tap for `hotkeys` on its own thread; nil when macOS refuses it (no permission after all). `fired` gets
    /// the index of a typed hotkey, on the tap's thread.
    init?(mode: Mode, hotkeys: [KeyCombo], fired: @escaping (Int) -> Void) {
        self.mode = mode
        self.fired = fired
        matcher = HotkeySequenceMatcher(hotkeys: hotkeys)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        // Unretained: the tap's thread holds the tap for as long as events can come (`run`).
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: mode == .active ? .defaultTap : .listenOnly, eventsOfInterest: mask,
                                           callback: { _, type, event, userInfo in
                                               guard let userInfo else { return Unmanaged.passUnretained(event) }
                                               let tap = Unmanaged<HotkeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                                               return tap.handle(type, event)
                                           },
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.warn("The keyboard event tap for left/right hotkeys could not be started")
            return nil
        }
        self.port = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in run(signalling: ready) }
        thread.name = "Greenshot hotkey tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        log.info("Keyboard event tap started (\(mode == .active ? "filtering" : "listening only")) for left/right hotkeys")
    }

    /// The tap's thread: runs its run loop until `stop()`. Holding `self` here keeps the tap alive while events can come.
    private func run(signalling ready: DispatchSemaphore) {
        let loop = CFRunLoopGetCurrent()
        runLoop = loop
        if let source { CFRunLoopAddSource(loop, source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
        ready.signal()
        CFRunLoopRun()
        if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
    }

    /// Stops the tap and its thread.
    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    /// On the tap's thread.
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
            let used = feed(chord, deviceFlags: flags.rawValue)
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

    /// True when the key belongs to a hotkey (complete, a step of one, or Esc ending one).
    private func feed(_ chord: KeyChord, deviceFlags: UInt64) -> Bool {
        switch matcher.feed(chord, deviceFlags: deviceFlags, at: Date()) {
        case .completed(let index):
            fired(index)
            return true
        case .pending, .cancelled:
            return true
        case .ignored:
            return false
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

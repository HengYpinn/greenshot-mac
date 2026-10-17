// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore

private let hotKeySignature: OSType = 0x4753_4D43 // "GSMC"
private let log = Log("Hotkeys")

/// Global hotkeys through Carbon's `RegisterEventHotKey` (upstream `HotkeyManager`). Unlike an event tap this
/// needs no Accessibility permission.
///
/// A hotkey can have several steps ("⌃⌥⌘K, C", upstream `HotkeySequence`). Carbon only reports registered keys, so
/// the first step of every hotkey is registered all the time, and while a hotkey is half typed the keys that may come
/// next (and Esc) are registered too, for at most `HotkeySequenceMatcher.chordTimeout` seconds.
///
/// A hotkey that needs the left or the right key of a modifier (upstream `ModifierLocation`) goes through a keyboard
/// event tap instead (`HotkeyEventTap`), only such hotkeys. Without the permission for the tap (Accessibility, or Input
/// Monitoring to only listen) it is registered on Carbon and works with either key; when the permission changes, the
/// hotkeys are registered again.
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

    // The hotkeys with a left or right side.
    private var tap: HotkeyEventTap?
    private var tapActions: [() -> Void] = []
    /// What is registered now, to register it again when the permission for the tap changes; nil while the hotkeys
    /// are off (a shortcut is being recorded).
    private var registered: (hotkeys: [KeyCombo], actions: [() -> Void])?
    private var registeredNames: [String]?
    /// The tap macOS refused although the permission allowed it: not tried again until the permissions change.
    private var refusedTapMode: HotkeyEventTap.Mode?
    private var permissionObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

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
        observePermissions()
    }

    /// Registers `hotkeys` with their actions, replacing the ones before. Returns the indices of the hotkeys macOS
    /// refused (another app may own their first step).
    @discardableResult
    func register(_ hotkeys: [KeyCombo], actions: [() -> Void]) -> [Int] {
        unregisterAll()
        registered = (hotkeys, actions)
        let tapped = startTap(for: hotkeys, actions: actions)
        // Carbon: every other hotkey; one with sides that has no tap works with either key.
        let carbonIndices = hotkeys.indices.filter { !tapped.contains($0) }
        let carbonHotkeys = carbonIndices.map { hotkeys[$0].ignoringSides }
        matcher = HotkeySequenceMatcher(hotkeys: carbonHotkeys)
        self.actions = carbonIndices.map { actions[$0] }
        var refused: Set<KeyChord> = []
        for chord in matcher.firstChords {
            if let registration = carbonRegister(chord) {
                registrations[registration.id] = registration.value
            } else {
                refused.insert(chord)
            }
        }
        return carbonIndices.indices.filter { refused.contains(carbonHotkeys[$0].firstChord) }.map { carbonIndices[$0] }
    }

    func unregisterAll() {
        endPending()
        registrations.values.forEach { UnregisterEventHotKey($0.ref) }
        registrations.removeAll()
        matcher = HotkeySequenceMatcher(hotkeys: [])
        actions = []
        tap?.stop()
        tap = nil
        tapActions = []
        registered = nil
        registeredNames = nil
    }

    // MARK: Left and right modifier keys

    /// Starts the event tap for the hotkeys with sides when the permissions allow it; returns their indices.
    private func startTap(for hotkeys: [KeyCombo], actions: [() -> Void]) -> Set<Int> {
        let sided = hotkeys.indices.filter { hotkeys[$0].usesSides }
        guard !sided.isEmpty else { return [] }
        guard let mode = HotkeyEventTap.availableMode else {
            log.info("No permission for left/right hotkeys: \(sided.count) of them work with either key")
            return []
        }
        // The tap matches the keys on its own thread and comes here only for a typed hotkey.
        guard let tap = HotkeyEventTap(mode: mode, hotkeys: sided.map { hotkeys[$0] }, fired: { [weak self] index in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.tappedHotkey(index) }
            }
        }) else {
            refusedTapMode = mode
            return []
        }
        refusedTapMode = nil
        self.tap = tap
        tapActions = sided.map { actions[$0] }
        return Set(sided)
    }

    /// The tap's hotkey with this index was typed.
    private func tappedHotkey(_ index: Int) {
        guard tapActions.indices.contains(index) else { return }
        tapActions[index]()
    }

    /// Accessibility and Input Monitoring post no notification of their own: look again when the app becomes active
    /// and when any app's Accessibility permission changed.
    private func observePermissions() {
        let local = NotificationCenter.default
        permissionObservers.append((local, local.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionsMayHaveChanged() }
        }))
        let distributed = DistributedNotificationCenter.default()
        permissionObservers.append((distributed, distributed.addObserver(forName: Notification.Name("com.apple.accessibility.api"),
                                                                         object: nil, queue: .main) { [weak self] _ in
            // The new value takes a moment to arrive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self?.permissionsMayHaveChanged() }
            }
        }))
    }

    /// Registers the hotkeys again when the tap the permissions allow is another one than the one running.
    private func permissionsMayHaveChanged() {
        let mode = HotkeyEventTap.availableMode
        guard let registered, registered.hotkeys.contains(where: \.usesSides), mode != tap?.mode,
              mode == nil || mode != refusedTapMode
        else { return }
        let names = registeredNames
        log.info("The permission for left/right hotkeys changed: registering the hotkeys again")
        let refused = register(registered.hotkeys, actions: registered.actions)
        if let names {
            registeredNames = names
            HotkeyDiagnostics.recordRegistration(names: names, combos: registered.hotkeys, refused: refused)
        }
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
        let refused = register(combos, actions: actions)
        registeredNames = names
        HotkeyDiagnostics.recordRegistration(names: names, combos: combos, refused: refused)
        let failed = refused.map { "\(names[$0]): \(combos[$0].displayString)" }
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
        // In the common modes, so the time also runs out while a menu or a modal window is open: until it does, the
        // next steps (Esc among them) belong to Greenshot system-wide.
        let timer = Timer(timeInterval: HotkeySequenceMatcher.chordTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPending() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timeout = timer
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
        // A menu can show neither several steps nor the side of a modifier.
        guard !isSequence, !usesSides else { return nil }
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

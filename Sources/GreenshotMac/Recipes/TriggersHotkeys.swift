// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The Hotkey triggers of the recipes, registered with the app's hotkeys (`HotkeyManager.registerAll`, RCP-061/322;
/// upstream `HotkeyTrigger`, `TriggerManager.RestartHotkeyTriggers`). They take the same way as the app's: Carbon, the
/// event tap for left/right modifiers, several steps through `HotkeySequenceMatcher`; Self-Service lists them, and a
/// settings change, "Register Again" or `greenshot-cli --reload` registers them again with the others.
@MainActor
enum RecipeHotkeyBindings {
    /// Posted when `clashes` changed (Settings › Recipes).
    static let clashesDidChange = Notification.Name("RecipeHotkeyClashesDidChange")

    /// The recipe hotkeys left out at the last registration, and why.
    private(set) static var clashes: [RecipeHotkeyClash] = []

    /// The recipe hotkeys to bind besides `taken` (the app's own, which win a clash); `name` reads "Recipe “Name”".
    static func current(excluding taken: [KeyCombo]) -> [(combo: KeyCombo, name: String, action: () -> Void)] {
        guard let runtime = RecipeRuntime.shared, runtime.isEnabled else {
            update(clashes: [])
            return []
        }
        let triggers = runtime.library.activeTriggers(ofTypes: [WellKnownTriggerType.hotkey])
            .compactMap { trigger in trigger.hotkey.map { (trigger: trigger, combo: $0) } }
        let candidates = triggers.map { NamedHotkey(name: name(of: $0.trigger), combo: $0.combo) }
        let names = appHotkeyNames()
        let fallback = String(localized: "a Greenshot hotkey", comment: "Names a hotkey of the app in a message about a recipe hotkey that clashes with it")
        let takenNamed = taken.map { combo in NamedHotkey(name: names.first { $0.combo == combo }?.name ?? fallback, combo: combo) }
        // Without the permission for left and right keys every hotkey is registered for either key (`HotkeyManager`).
        let resolved = RecipeHotkeyClashes.resolve(candidates, taken: takenNamed, tellsSides: HotkeyEventTap.availableMode != nil)
        update(clashes: resolved.clashes)
        return resolved.kept.map { index in
            let trigger = triggers[index].trigger
            return (combo: candidates[index].combo, name: candidates[index].name, action: { fire(trigger) })
        }
    }

    private static func name(of trigger: ActiveRecipeTrigger) -> String {
        let triggerName = trigger.trigger.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let recipeName = trigger.recipeName
        return triggerName.isEmpty ? String(localized: "Recipe “\(recipeName)”") : String(localized: "Recipe “\(recipeName)” (\(triggerName))")
    }

    /// The trigger situation is taken at the key press, before anything else comes to the front.
    private static func fire(_ trigger: ActiveRecipeTrigger) {
        let info = RecipeRuntime.triggerInfo(for: trigger)
        guard let runtime = RecipeRuntime.shared else { return }
        log.info("Hotkey of recipe '\(trigger.recipeId)' pressed")
        if case .notStarted = runtime.fire(trigger, info: info) {
            log.info("The hotkey of recipe '\(trigger.recipeId)' started nothing: the recipe or the trigger is off.")
        }
    }

    /// The names `HotkeyManager.registerAll` gives the app's hotkeys, for the clash messages.
    private static func appHotkeyNames() -> [(name: String, combo: KeyCombo)] {
        guard let hotkeys = RecipeAppUI.settings?.value.hotkeys else { return [] }
        let all: [(String, KeyCombo?)] = [
            (String(localized: "Capture region"), hotkeys.region), (String(localized: "Capture window"), hotkeys.window),
            (String(localized: "Capture full screen"), hotkeys.fullScreen), (String(localized: "Capture last region"), hotkeys.lastRegion),
            (String(localized: "Capture text"), hotkeys.text), (String(localized: "Start or stop recording"), hotkeys.recordVideo),
            (String(localized: "Open image from clipboard"), hotkeys.clipboard)
        ]
        return all.compactMap { name, combo in combo.map { (name: name, combo: $0) } }
    }

    private static func update(clashes newClashes: [RecipeHotkeyClash]) {
        guard newClashes != clashes else { return }
        for clash in newClashes where !clashes.contains(clash) {
            log.warn("Recipe hotkey not registered: \(clash.text)")
        }
        clashes = newClashes
        NotificationCenter.default.post(name: clashesDidChange, object: nil)
    }
}

/// The hub's source for Hotkey triggers: when the active ones change it registers every hotkey again (the app's and the
/// recipes'), unless the shortcut recorder has them off; its end registers them anyway.
@MainActor
final class RecipeHotkeyTriggerSource: RecipeTriggerSource {
    let triggerTypes: Set<String> = [WellKnownTriggerType.hotkey]

    /// An active Hotkey trigger as registered: by its keys (key codes, modifiers, sides), not their names, which follow
    /// the keyboard layout, so switching layouts registers nothing again.
    private struct Registered: Equatable {
        var recipeId: String
        var key: String
        var hotkey: KeyCombo?
    }

    private let reregister: () -> Void
    private var registered: [Registered] = []
    private var recording = false
    private var observers: [NSObjectProtocol] = []

    init(reregister: @escaping () -> Void) {
        self.reregister = reregister
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ShortcutRecorderButton.recordingDidBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recording = true }
        })
        observers.append(center.addObserver(forName: ShortcutRecorderButton.recordingDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recording = false }
        })
    }

    func sync(_ triggers: [ActiveRecipeTrigger]) {
        let signature = triggers.map { Registered(recipeId: $0.recipeId.lowercased(), key: $0.key, hotkey: $0.hotkey) }
        guard signature != registered else { return }
        registered = signature
        guard !recording else { return }
        log.info("The recipe hotkeys changed (\(triggers.count) active): registering the hotkeys again")
        reregister()
    }

    func stop() {
        registered = []
    }
}

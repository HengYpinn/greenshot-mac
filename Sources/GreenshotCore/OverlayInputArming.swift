// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// When the capture screen takes input (Mac only). The screen takes the keyboard from the app the user is typing in, and
/// a capture that greenshot-cli, a link or a recipe of those started opens without the user having asked for it: the
/// keys of the sentence the user was typing ("see you tomorrow", Return) would pick a window (Space, Return) and send
/// its picture to the destinations. So an overlay the user did not start themselves ignores every key but Escape, and
/// ignores a mouse button that is released, until a mouse-down happened on it a second after it appeared: only a
/// deliberate click shows that the user is at the screen. That press shows only that (`armedByLastMouseDown`; the rest
/// of a double click it starts counts for nothing): in the text mode its click alone copies no line, a drag that starts
/// with it still selects words; a region needs a drag anyway. An overlay the user started (hotkey, menu) takes input at
/// once.
public struct OverlayInputArming: Sendable, Equatable {
    /// The same second as the consent questions' buttons (`ConsentArming.delay`).
    public static let delay: TimeInterval = 1

    public let requiresArming: Bool
    public let shownAt: Date
    public private(set) var isArmed: Bool
    /// The last mouse-down armed the overlay: the user's first deliberate press, which doesn't choose what to take.
    public private(set) var armedByLastMouseDown = false

    public init(requiresArming: Bool, shownAt: Date) {
        self.requiresArming = requiresArming
        self.shownAt = shownAt
        self.isArmed = !requiresArming
    }

    /// A mouse-down on the overlay: it arms the overlay when the delay has passed; true when it did, or the overlay was
    /// armed already (the click counts). `clickCount` is the event's: the further presses of a double or triple click
    /// that started with the arming press belong to it and don't count (false; the overlay stays armed).
    @discardableResult
    public mutating func mouseDown(at now: Date, clickCount: Int) -> Bool {
        if armedByLastMouseDown, clickCount > 1 { return false }
        armedByLastMouseDown = false
        if !isArmed, now.timeIntervalSince(shownAt) >= Self.delay {
            isArmed = true
            armedByLastMouseDown = true
        }
        return isArmed
    }

    /// Escape always cancels; every other key needs the overlay to be armed.
    public func allowsKey(isEscape: Bool) -> Bool {
        isEscape || isArmed
    }

    /// Whether the buttons of the mouse may start, change or complete a selection.
    public var allowsMouse: Bool { isArmed }

    /// Whether a flow started by this kind of trigger has the user at the capture screen. An allowlist: the hotkey, the
    /// menus, a start from the recipe list or the editor are the user's own; a command line, a link, an AI tool, a
    /// schedule, the browser extension or a file are not. No trigger (a test run) is the user's.
    public static func startedByUser(triggerType: String?, markedByAutomation: Bool = false) -> Bool {
        guard !markedByAutomation else { return false }
        guard let triggerType else { return true }
        let own = [WellKnownTriggerType.hotkey, WellKnownTriggerType.contextMenu, WellKnownTriggerType.systray,
                   WellKnownTriggerType.manual, WellKnownTriggerType.editor]
        return own.contains { $0.caseInsensitiveCompare(triggerType) == .orderedSame }
    }

    /// The mark a built-in capture that automation started carries into the recipe that replaced it (a run request's
    /// objects, `RecipeFlowContext.object(forKey:)`): its trigger is the menu's Manual one, so the trigger can't say it.
    public static let automationMarkKey = "StartedByAutomation"
}

/// The value under `OverlayInputArming.automationMarkKey`.
public struct AutomationStartMark: Sendable {
    public init() {}
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

private let log = Log("Recipes")

/// The app's own writes to the clipboard, which the Clipboard trigger (RCP-065) must not take for a copy in another app.
/// Every place that writes `NSPasteboard.general` calls `recordWrite` after the write (Clipboard.copy, RSTEPS's
/// Clipboard step and clipboard writer).
@MainActor
enum OwnPasteboardWrites {
    private(set) static var lastChangeCount: Int?

    static func recordWrite(_ pasteboard: NSPasteboard) {
        lastChangeCount = pasteboard.changeCount
    }
}

/// The hub's source for Clipboard triggers (upstream `ClipboardTrigger`). macOS posts no notification for a clipboard
/// change, so while at least one Clipboard trigger is active the change count is read twice a second; with none the
/// timer is gone. A change is looked at by its types first (no paste alert on macOS 15.4 and later); files and HTML are
/// read only when a trigger wants an image and no image type is there. Greenshot's own copies, password managers'
/// (concealed) and transient copies are left alone.
@MainActor
final class RecipeClipboardTriggerSource: RecipeTriggerSource {
    let triggerTypes: Set<String> = [WellKnownTriggerType.clipboard]
    static let interval: TimeInterval = 0.5

    private let pasteboard: NSPasteboard
    private let fire: (ActiveRecipeTrigger, [String: JSONValue]) -> Void
    private var triggers: [ActiveRecipeTrigger] = []
    private var timer: Timer?
    private var lastSeen = 0

    /// `fire` gets the trigger and its variables; it takes the trigger situation itself, right away.
    init(pasteboard: NSPasteboard = .general, fire: @escaping (ActiveRecipeTrigger, [String: JSONValue]) -> Void) {
        self.pasteboard = pasteboard
        self.fire = fire
    }

    var isWatching: Bool { timer != nil }

    func sync(_ triggers: [ActiveRecipeTrigger]) {
        self.triggers = triggers
        if triggers.isEmpty { stopTimer() } else { startTimer() }
    }

    func stop() {
        triggers = []
        stopTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        // Upstream skips the clipboard as it is when the trigger starts: only later copies count.
        lastSeen = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = Self.interval / 2
        // Also while a menu is open or a modal window runs.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        log.info("Watching the clipboard for \(triggers.count) recipe trigger(s)")
    }

    private func stopTimer() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        log.info("Stopped watching the clipboard: no recipe has an active Clipboard trigger")
    }

    /// One look at the clipboard: nothing to do unless its change count moved.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastSeen else { return }
        lastSeen = count
        guard count != OwnPasteboardWrites.lastChangeCount else { return }
        let change = RecipeClipboardChange(types: pasteboard.types?.map(\.rawValue) ?? [])
        guard !change.types.isEmpty else { return }
        if let reason = change.ignoredReason {
            log.debug("Clipboard change ignored: \(reason)")
            return
        }
        var containsImage: Bool?
        for trigger in triggers {
            let config = trigger.trigger
            var image = false
            if config.onImageCopied {
                if containsImage == nil { containsImage = change.hasImageType || (change.mayContainImage && contentHasImage(change)) }
                image = containsImage ?? false
            }
            guard RecipeClipboardChange.fires(onImageCopied: config.onImageCopied, formatFilter: config.formatFilter, change: change,
                                              containsImage: image) else { continue }
            log.info("Clipboard trigger of recipe '\(trigger.recipeId)' fired (formats: \(change.formats.joined(separator: ", ")))")
            fire(trigger, change.variables)
        }
    }

    /// Upstream `ContainsImageAsync`: copied image files, or HTML with a picture. Reading them may show macOS's paste
    /// alert, so this runs only when a trigger wants an image and the types have none.
    private func contentHasImage(_ change: RecipeClipboardChange) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                              .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: options), !files.isEmpty { return true }
        if let html = pasteboard.string(forType: .html), !ImagePasteboard.imageURLs(in: html).isEmpty { return true }
        return false
    }
}

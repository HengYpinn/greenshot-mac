// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

private let log = Log("AITools")

/// The AI tools consent between the settings and their seal (`AIToolsConsentSeal`): which sealed values are stored,
/// which are in effect, when they are sealed, and when the key is read or written. `SettingsStore` keeps the settings
/// and takes their sealed values from here.
///
/// - The stored values count once their seal was checked (`check`): at the start, a reload, Retry in Settings › AI
///   Tools, or a change of the consent. While the key can't be read (a locked Keychain, its prompt cancelled or denied)
///   they are kept as they are, and the reset values (nobody allowed) are in effect.
/// - A change of the consent is sealed first and stored second. A change that can't be sealed:
///   - allows more (a program allowed or replaced, an exclusion removed, the notification off): it is in effect until
///     Greenshot quits; the stored values and their seal stay as they are.
///   - allows less (a program removed, an exclusion added, the notification on): it takes effect and is stored at once,
///     without a seal, so the next start resets the consent (nobody allowed), which keeps the restriction. If the
///     stored values were checked, the key is removed too, so their old seal can't verify them again when someone puts
///     them back (the stored values in memory are sealed again with a new key).
///   Both are sealed together with the stored values as soon as a check succeeds in this run.
/// - A save of the settings that doesn't change the consent doesn't use the Keychain (`settingsSaved`).
public struct AIToolsConsentKeeper {
    /// What the user is told, once until a check succeeds again, when a change couldn't be sealed.
    public enum Notice: Hashable, Sendable {
        /// A change that allows more is in effect until Greenshot quits.
        case untilQuit
        /// A change that allows less is stored without its seal: the next start resets the consent.
        case storedUnsealed
    }

    /// What Settings › AI Tools shows about the consent.
    public struct Status: Equatable, Sendable {
        /// The stored consent couldn't be checked: in effect nobody is allowed, plus this run's changes.
        public var isUnverifiable = false
        /// Changes of this run that allow more are in effect but not stored: they end when Greenshot quits.
        public var hasChangesUntilQuit = false
        /// The stored consent has no valid seal: the next start resets it.
        public var isStoredUnsealed = false
        /// Why the Keychain couldn't be used (its message); nil once it could.
        public var problem: String?

        public init() {}

        /// Something to show, with Retry.
        public var needsAttention: Bool { isUnverifiable || hasChangesUntilQuit || isStoredUnsealed }
    }

    /// A change of the sealed values as what was added and removed, so it can be made again to other values: to the
    /// checked stored ones after it was made to the reset ones in effect.
    struct Change: Equatable {
        /// Allowed-list lines added; an entry of the same program (another Team ID) is replaced, like
        /// `AIToolAccess.allowing` does.
        var allowed: [String] = []
        /// Allowed-list lines removed.
        var disallowed: [String] = []
        var excluded: [String] = []
        var unexcluded: [String] = []
        var notifyOnCapture: Bool?

        init() {}

        init(from before: AIToolsSettings, to after: AIToolsSettings) {
            allowed = after.allowedClients.filter { !before.allowedClients.contains($0) }
            disallowed = before.allowedClients.filter { !after.allowedClients.contains($0) }
            excluded = after.excludedApplications.filter { !before.excludedApplications.contains($0) }
            unexcluded = before.excludedApplications.filter { !after.excludedApplications.contains($0) }
            notifyOnCapture = after.notifyOnCapture == before.notifyOnCapture ? nil : after.notifyOnCapture
        }

        var isEmpty: Bool { self == Change() }

        /// The part that allows more: programs allowed, with the entries of the same programs they replace, exclusions
        /// removed, the notification off.
        var grant: Change {
            var part = Change()
            part.allowed = allowed
            part.disallowed = disallowed.filter(isReplaced)
            part.unexcluded = unexcluded
            part.notifyOnCapture = notifyOnCapture == false ? false : nil
            return part
        }

        /// The part that allows less: programs removed, exclusions added, the notification on.
        var restriction: Change {
            var part = Change()
            part.disallowed = disallowed.filter { !isReplaced($0) }
            part.excluded = excluded
            part.notifyOnCapture = notifyOnCapture == true ? true : nil
            return part
        }

        /// An allowed-list line of a program this change allows again (another Team ID).
        private func isReplaced(_ line: String) -> Bool {
            allowed.contains { Self.sameProgram($0, line) }
        }

        private static func sameProgram(_ a: String, _ b: String) -> Bool {
            AIToolAllowedEntry(parsing: a).key.caseInsensitiveCompare(AIToolAllowedEntry(parsing: b).key) == .orderedSame
        }

        /// `settings` with this change made.
        func applied(to settings: AIToolsSettings) -> AIToolsSettings {
            var result = settings
            result.allowedClients.removeAll { disallowed.contains($0) }
            for line in allowed {
                result.allowedClients.removeAll { Self.sameProgram($0, line) }
                result.allowedClients.append(line)
            }
            result.excludedApplications.removeAll { unexcluded.contains($0) }
            for name in excluded {
                let normalized = AIToolExclusion.normalize(name)
                if !result.excludedApplications.contains(where: { AIToolExclusion.normalize($0) == normalized }) {
                    result.excludedApplications.append(name)
                }
            }
            if let notifyOnCapture { result.notifyOnCapture = notifyOnCapture }
            return result
        }
    }

    /// A change of this run that isn't sealed yet; `isStored`: one that allows less, stored at once without a seal.
    private struct Pending {
        var change: Change
        var isStored: Bool
    }

    private let seal: AIToolsConsentSeal
    /// The sealed values as read or as last sealed: what the stored seal is for, if it is valid.
    private var base: AIToolsSettings
    /// `base` was checked in this run: its seal verified, or Greenshot reset or sealed it.
    private var isChecked = false
    /// The stored seal verifies `base` (or `base` is the defaults, which need none).
    private var isBaseSealed = false
    /// This run's changes since `base`, oldest first.
    private var changes: [Pending] = []
    /// The seal text verified or written in this run (nil: none), to notice a replaced seal without the key.
    private var knownSeal: String?
    /// Why the Keychain couldn't be used the last time; nil once it could.
    private var problem: String?
    /// The key couldn't be read at the last check: logged once, not at every check while it stays so.
    private var loggedUnverifiable = false
    /// What the user was told since the last check that succeeded.
    private var told: Set<Notice> = []

    /// The consent as loaded at the start, checked (`check`).
    public init(seal: AIToolsConsentSeal, loaded settings: AIToolsSettings) {
        self.seal = seal
        base = settings
        check()
    }

    // MARK: Values

    /// The sealed values to store with the settings: the checked or unchecked stored ones (a reset, when their seal was
    /// wrong) with this run's changes that allow less.
    public var stored: AIToolsSettings {
        changes.filter(\.isStored).reduce(base) { $1.change.applied(to: $0) }
    }

    /// The sealed values in effect: the stored ones (the reset values while they aren't checked) with every change of
    /// this run.
    public var inEffect: AIToolsSettings {
        changes.reduce(startOfEffect) { $1.change.applied(to: $0) }
    }

    private var startOfEffect: AIToolsSettings {
        isChecked ? base : AIToolsConsentSeal.reset(base)
    }

    public var status: Status {
        var status = Status()
        status.isUnverifiable = !isChecked
        let withoutGrants = changes.filter(\.isStored).reduce(startOfEffect) { $1.change.applied(to: $0) }
        status.hasChangesUntilQuit = !AIToolsConsentSeal.sealedValuesEqual(inEffect, withoutGrants)
        status.isStoredUnsealed = isStoredUnsealed
        status.problem = problem
        return status
    }

    /// What is stored has no seal that verifies it: the next start resets it. Not for the defaults (they need none),
    /// and not for unchecked values without changes (their seal may well verify them).
    private var isStoredUnsealed: Bool {
        let stored = stored
        if AIToolsConsentSeal.isDefault(stored) { return false }
        if isChecked && !isBaseSealed { return true }
        return !AIToolsConsentSeal.sealedValuesEqual(stored, base)
    }

    // MARK: Checking and sealing

    /// Checks the stored values if they weren't (reads the key), then seals what isn't: this run's changes, values that
    /// were reset, or the values of a stored seal that isn't the one of this run (writes the key). True when everything
    /// is sealed now. The start, a reload, Retry and every change of the consent check.
    @discardableResult
    public mutating func check() -> Bool {
        guard isChecked || verifyBase() else { return false }
        if isBaseSealed && changes.isEmpty && seal.storedSeal == knownSeal {
            problem = nil
            return true
        }
        return sealEverything()
    }

    /// Checks `base` against the stored seal: valid, it counts; invalid, it is reset (restricts only, so it counts too);
    /// the key can't be read, it stays unchecked.
    private mutating func verifyBase() -> Bool {
        if AIToolsConsentSeal.isDefault(base) {
            isChecked = true
            isBaseSealed = true
            knownSeal = seal.storedSeal
            return true
        }
        let sealed: Bool
        do {
            sealed = try seal.isSealed(base)
        } catch {
            problem = error.localizedDescription
            if !loggedUnverifiable {
                loggedUnverifiable = true
                log.warn("The AI tools consent can't be checked: its key can't be read from the Keychain (locked, or its prompt was cancelled or denied: \(error.localizedDescription)). AI tools are asked as if none were allowed until it can be read; the stored consent is kept.")
            }
            return false
        }
        loggedUnverifiable = false
        isChecked = true
        if sealed {
            isBaseSealed = true
            knownSeal = seal.storedSeal
        } else {
            base = AIToolsConsentSeal.reset(base)
            isBaseSealed = false
            log.warn("The AI tools settings were changed outside Greenshot, or saved without their seal while the Keychain couldn't be used, and are not trusted. They were reset and AI tools will be asked again.")
        }
        return true
    }

    /// Seals the values in effect (the checked ones with every change) and takes them as the stored ones.
    private mutating func sealEverything() -> Bool {
        let sealing = inEffect
        do {
            try seal.save(sealing)
        } catch {
            problem = error.localizedDescription
            return false
        }
        base = sealing
        changes = []
        isBaseSealed = true
        knownSeal = seal.storedSeal
        problem = nil
        told = []
        return true
    }

    // MARK: Changes

    /// `edited` (the values in effect, `current`, with the user's edit) with the values an administrator locked
    /// (`policy`) as they are in effect: those are the administrator's, and a change of them isn't one of the user's.
    public static func userEdit(_ edited: AIToolsSettings, of current: AIToolsSettings, policy: ManagedPolicy) -> AIToolsSettings {
        var result = edited
        if policy.isLocked(\AppSettings.aiTools.allowedClients) { result.allowedClients = current.allowedClients }
        if policy.isLocked(\AppSettings.aiTools.excludedApplications) { result.excludedApplications = current.excludedApplications }
        if policy.isLocked(\AppSettings.aiTools.notifyOnCapture) { result.notifyOnCapture = current.notifyOnCapture }
        return result
    }

    /// The user changed the consent in effect from `before` to `after` (`inEffect` with the edit). It is checked and
    /// sealed first; `stored` is then what to save. A change that can't be sealed is kept as this type's doc says, and
    /// the notice returned (once until a check succeeds) is what to tell the user.
    public mutating func change(from before: AIToolsSettings, to after: AIToolsSettings) -> Notice? {
        let change = Change(from: before, to: after)
        guard !change.isEmpty else { return nil }
        let storedBefore = stored
        let restriction = change.restriction
        let grant = change.grant
        if !restriction.isEmpty { changes.append(Pending(change: restriction, isStored: true)) }
        if !grant.isEmpty { changes.append(Pending(change: grant, isStored: false)) }
        guard !check() else { return nil }

        let restricted = !AIToolsConsentSeal.sealedValuesEqual(storedBefore, stored)
        if restricted {
            log.warn("A change of the AI tools consent that allows less can't be sealed (\(problem ?? "")): it is stored without its seal, so the consent is reset at the next start unless it is sealed before.")
            if isChecked { removeKeyOfOldSeal() }
        }
        if !grant.isEmpty {
            log.warn("A change of the AI tools consent that allows more can't be sealed (\(problem ?? "")): it applies until Greenshot quits unless it is sealed before.")
        }
        let notice: Notice? = restricted ? .storedUnsealed : grant.isEmpty ? nil : .untilQuit
        guard let notice, told.insert(notice).inserted else { return nil }
        return notice
    }

    /// The stored values allow less than the old seal says, and the values in memory don't need that seal any more:
    /// without its key it can't verify the old values when someone puts them back with it.
    private mutating func removeKeyOfOldSeal() {
        do {
            try seal.removeKey()
            isBaseSealed = false
        } catch {
            log.warn("The key of the AI tools consent could not be removed (\(error.localizedDescription)).")
        }
    }

    // MARK: Saving and reloading

    /// After a save of the settings that didn't change the consent: seals the stored values again when the stored seal
    /// isn't the one verified or written in this run (removed or replaced outside Greenshot). Compares the seal's text
    /// only, never reads the key, and does nothing while something isn't checked or sealed: that waits for the next
    /// check, so a locked Keychain isn't asked at every save.
    public mutating func settingsSaved() {
        guard isChecked, isBaseSealed, changes.isEmpty, seal.storedSeal != knownSeal else { return }
        log.warn("The seal of the AI tools consent was removed or replaced outside Greenshot; the consent in use is sealed again.")
        do {
            try seal.save(base)
            knownSeal = seal.storedSeal
            problem = nil
        } catch {
            isBaseSealed = false
            problem = error.localizedDescription
            log.warn("The AI tools consent could not be sealed again (\(error.localizedDescription)); it is reset at the next start unless it is sealed before.")
        }
    }

    /// The settings were read again (`greenshot-cli --reload`): the sealed values `stored` keep what is known about
    /// them, others are checked like at the start. This run's changes stay and are made to them.
    public mutating func reload(_ settings: AIToolsSettings) {
        if !AIToolsConsentSeal.sealedValuesEqual(settings, stored) {
            base = settings
            isChecked = false
            isBaseSealed = false
            knownSeal = nil
        }
        check()
    }
}

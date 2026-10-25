// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// What Settings › Destinations shows for the secrets of the uploads (the Jira and Confluence tokens, the Box client
// secret, the Box and Dropbox sign-ins) when the secret store can't be read. Upstream keeps them in its ini file, which
// can always be read; the Keychain can be locked.

/// What reading or saving a secret gave, as Settings shows it.
public enum SecretState: Equatable, Sendable {
    /// Read or saved (there may be none).
    case usable
    /// The store can't be used right now (`SecretStoreUnavailableError`: the Keychain is locked, or its prompt was
    /// cancelled or denied). What is stored is unknown and still there: the field is disabled and the account offers
    /// neither Sign In nor Sign Out, which would replace it, only Retry.
    case unavailable(String)
    /// Another error, e.g. a damaged item. Reading again would give the same, so the field stays editable and the
    /// account keeps Sign In: a new secret or sign-in replaces the item.
    case failed(String)

    /// The state after a read or save that threw `error` (nil: it worked).
    public init(error: Error?) {
        guard let error else {
            self = .usable
            return
        }
        self = error is SecretStoreUnavailableError ? .unavailable(error.localizedDescription) : .failed(error.localizedDescription)
    }

    /// The error to show.
    public var message: String? {
        switch self {
        case .usable: return nil
        case .unavailable(let message), .failed(let message): return message
        }
    }

    /// Disabled, with Retry.
    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

/// What the Box or Dropbox row of Settings offers.
public enum CloudAccountAction: Equatable, Sendable {
    case signIn
    /// Removes the stored tokens only: it needs neither the Box client secret nor a read of the tokens.
    case signOut
    /// The store can't be used: whether there is an account is unknown.
    case retry

    public init(signedIn: Bool, state: SecretState) {
        if state.isUnavailable {
            self = .retry
        } else {
            self = signedIn ? .signOut : .signIn
        }
    }
}

/// A secret shown in Settings (see `SecretRetryList`).
@MainActor
public protocol RetryableSecret: AnyObject {
    /// What the last read or save gave.
    var secretState: SecretState { get }
    /// Retry: reads the secret again, or saves the edit the store refused, and shows the result.
    func tryAgain()
}

/// The secrets one window shows. Each read of a locked Keychain shows its password prompt: while one of them can't be
/// read, the others don't read on their own (`readUnlessUnavailable`), and one Retry reads them all again.
@MainActor
public final class SecretRetryList {
    private struct Entry {
        weak var secret: (any RetryableSecret)?
    }

    private var entries: [Entry] = []

    public init() {}

    /// The secrets shown, in the order they were added.
    private var secrets: [any RetryableSecret] { entries.compactMap(\.secret) }

    public func add(_ secret: any RetryableSecret) {
        entries.removeAll { $0.secret == nil }
        entries.append(Entry(secret: secret))
    }

    /// The state of a secret shown that the store couldn't be used for, nil when there is none.
    public var unavailable: SecretState? {
        secrets.lazy.map(\.secretState).first(where: \.isUnavailable)
    }

    /// A read the user didn't ask for (a field shown, a row appearing): `read`, unless a secret shown can't be read. The
    /// Keychain is most likely still locked then, and asking again would only show the same prompt, so no read until
    /// Retry: a secret read before keeps `current` (macOS denies items one by one: another item's "locked" isn't its
    /// own), one never read (`current` nil) takes the unavailable secret's state.
    public func readUnlessUnavailable(keeping current: SecretState? = nil, _ read: () -> SecretState) -> SecretState {
        guard let unavailable else { return read() }
        return current ?? unavailable
    }

    /// Retry on `pressed`: reads it again, then every other secret that couldn't be read, in the order they were added,
    /// and stops at the first that still can't. Once the Keychain is unlocked one press reads them all; while it is
    /// locked (or an item is denied) a press shows one prompt that the user refuses, not one per secret.
    public func retry(from pressed: any RetryableSecret) {
        pressed.tryAgain()
        guard !pressed.secretState.isUnavailable else { return }
        for secret in secrets where secret !== pressed && secret.secretState.isUnavailable {
            secret.tryAgain()
            if secret.secretState.isUnavailable { return }
        }
    }
}

/// A secret edited like a setting (a token field of Settings › Destinations): read when shown, saved at every edit.
@MainActor
public final class EditableSecret: RetryableSecret {
    /// What the field shows: the stored secret, or what was typed.
    public private(set) var text: String
    public private(set) var secretState: SecretState
    /// Called before `text` or `secretState` change, so the field shows them (also after a Retry pressed elsewhere).
    public var willChange: (() -> Void)?
    /// `text` is an edit the store refused because it couldn't be used (the Keychain locked while typing): Retry saves
    /// it instead of reading what is stored, which may be only its first characters (every keystroke is saved).
    private var editRefused = false
    private let read: @MainActor () throws -> String?
    private let write: @MainActor (String) throws -> Void

    /// Reads the secret, unless a secret of `list` can't be read (`SecretRetryList.readUnlessUnavailable`), and adds it
    /// to `list`.
    public init(list: SecretRetryList, read: @escaping @MainActor () throws -> String?,
                write: @escaping @MainActor (String) throws -> Void) {
        self.read = read
        self.write = write
        var secret = ""
        secretState = list.readUnlessUnavailable {
            do {
                secret = try read() ?? ""
                return .usable
            } catch {
                return SecretState(error: error)
            }
        }
        text = secret
        list.add(self)
    }

    /// The user changed the text: saved at once.
    public func edit(_ newText: String) {
        guard newText != text else { return }
        willChange?()
        text = newText
        save()
    }

    public func tryAgain() {
        willChange?()
        guard !editRefused else {
            save()
            return
        }
        do {
            text = try read() ?? ""
            secretState = .usable
        } catch {
            text = ""
            secretState = SecretState(error: error)
        }
    }

    private func save() {
        do {
            try write(text)
            secretState = .usable
        } catch {
            secretState = SecretState(error: error)
        }
        editRefused = secretState.isUnavailable
    }
}

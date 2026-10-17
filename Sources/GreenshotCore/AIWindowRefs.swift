// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Window ids for AI tools (upstream `Ai/AiWindowRefs.cs`): `list_windows` hands out short ids like "w7" instead of
/// window numbers, and a Window argument only takes such an id, so an AI tool can only capture windows Greenshot listed
/// to it:
/// - the ids belong to one AI tool and greenshot-mcp process (`scope`); another program or a new session can't use them,
/// - they expire `lifetime` after the last listing that showed the window,
/// - windows of excluded apps never get one (the caller doesn't register them),
/// - an id stops working when the window is closed (also when its number now belongs to another process).
public final class AIWindowRefs: @unchecked Sendable {
    /// How long an id stays valid after `list_windows` showed the window (upstream 10 minutes).
    public static let lifetime: TimeInterval = 10 * 60
    /// The most ids kept per AI tool; the oldest go.
    public static let maximumPerScope = 2000
    public static let staleMessage = "Call list_windows again and use a window id from its result."

    private struct Entry {
        var id: String
        var window: CGWindowID
        var processID: pid_t
        var expires: Date
    }

    private struct Scope {
        var byId: [String: Entry] = [:]
        var byWindow: [CGWindowID: String] = [:]
    }

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let ownerOf: @Sendable (CGWindowID) -> pid_t?
    // Ids are never reused while the app runs, so an old id can't point to another window
    private var nextNumber = 1
    private var scopes: [String: Scope] = [:]

    /// - Parameters:
    ///   - now: the clock (tests).
    ///   - ownerOf: the process of a window, nil when the window doesn't exist any more.
    public init(now: @escaping @Sendable () -> Date = { Date() }, ownerOf: @escaping @Sendable (CGWindowID) -> pid_t?) {
        self.now = now
        self.ownerOf = ownerOf
    }

    /// The id of this window for this AI tool: the same window keeps its id while it is valid.
    public func register(scope key: String, window: CGWindowID, processID: pid_t) -> String {
        let time = now()
        return lock.withLock {
            pruneScopes(time)
            var scope = scopes[key] ?? Scope()
            if let id = scope.byWindow[window], var entry = scope.byId[id] {
                if entry.processID == processID {
                    entry.expires = time.addingTimeInterval(Self.lifetime)
                    scope.byId[id] = entry
                    scopes[key] = scope
                    return id
                }
                // The window number belongs to another process now
                remove(id, from: &scope)
            }
            let entry = Entry(id: "w\(nextNumber)", window: window, processID: processID, expires: time.addingTimeInterval(Self.lifetime))
            nextNumber += 1
            scope.byId[entry.id.lowercased()] = entry
            scope.byWindow[window] = entry.id.lowercased()
            if scope.byId.count > Self.maximumPerScope {
                let oldest = scope.byId.values.sorted { $0.expires < $1.expires }.prefix(scope.byId.count - Self.maximumPerScope)
                for old in oldest { remove(old.id.lowercased(), from: &scope) }
            }
            scopes[key] = scope
            return entry.id
        }
    }

    /// The window of an id from `list_windows`, for the AI tool that got it; else the error for the AI tool (unknown,
    /// expired, another AI tool's, or the window is gone).
    public func resolve(scope key: String, reference: String) -> Result<CGWindowID, AIToolError> {
        let id = reference.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return .failure(AIToolError("A window id from list_windows is needed. " + Self.staleMessage)) }
        let time = now()
        let found: Entry? = lock.withLock {
            guard var scope = scopes[key] else { return nil }
            removeExpired(&scope, time)
            scopes[key] = scope
            return scope.byId[id.lowercased()]
        }
        guard let entry = found else { return .failure(AIToolError("'\(id)' is not a current window id. " + Self.staleMessage)) }
        guard let owner = ownerOf(entry.window), owner == entry.processID else {
            lock.withLock {
                if var scope = scopes[key] {
                    remove(id.lowercased(), from: &scope)
                    scopes[key] = scope
                }
            }
            return .failure(AIToolError("The window '\(id)' was closed. " + Self.staleMessage))
        }
        return .success(entry.window)
    }

    /// Forgets every id (tests).
    func clear() {
        lock.withLock { scopes = [:] }
    }

    private func pruneScopes(_ time: Date) {
        for key in scopes.keys {
            guard var scope = scopes[key] else { continue }
            removeExpired(&scope, time)
            scopes[key] = scope.byId.isEmpty ? nil : scope
        }
    }

    private func removeExpired(_ scope: inout Scope, _ time: Date) {
        for (id, entry) in scope.byId where entry.expires <= time {
            remove(id, from: &scope)
        }
    }

    private func remove(_ id: String, from scope: inout Scope) {
        guard let entry = scope.byId.removeValue(forKey: id) else { return }
        if scope.byWindow[entry.window] == id { scope.byWindow.removeValue(forKey: entry.window) }
    }
}

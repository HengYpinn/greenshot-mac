// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// What the user approved for one recipe of a file (upstream `RecipeApproval`).
public struct RecipeApproval: Sendable, Codable, Equatable {
    public var recipeId: String
    /// Keys from `RecipeApprovalPolicy.triggerKey`.
    public var approvedTriggers: [String] = []
    public var allTriggers: Bool = false
    public var allowedGates: [RecipeGateType] = []
    public var replacesBuiltIn: Bool = false

    public init(recipeId: String, approvedTriggers: [String] = [], allowedGates: [RecipeGateType] = []) {
        self.recipeId = recipeId
        self.approvedTriggers = approvedTriggers
        self.allowedGates = allowedGates
    }

    public func isTriggerApproved(_ key: String) -> Bool {
        allTriggers || approvedTriggers.contains { recipeEquals($0, key) }
    }
    public func isGateAllowed(_ gate: RecipeGateType) -> Bool { allowedGates.contains(gate) }
}

/// The approval of a file's exact content (upstream `RecipeTrustRecord`).
public struct RecipeTrustRecord: Sendable, Codable, Equatable {
    /// Origin of a recipe an AI tool wrote: "ai:" and the tool's name.
    public static let aiOriginPrefix = "ai:"

    /// The standardized path, compared case-insensitively.
    public var filePath: String
    /// SHA-256 of the file bytes, lowercase hex.
    public var sha256: String
    public var approvedAt: Date
    public var recipeName: String?
    public var recipeVersion: String?
    public var origin: String?
    /// The approved text (up to 256 KB), to show the changes when the file changes.
    public var approvedContent: String?
    public var recipes: [RecipeApproval] = []

    public init(filePath: String, sha256: String, approvedAt: Date = Date()) {
        self.filePath = filePath
        self.sha256 = sha256
        self.approvedAt = approvedAt
    }

    public var isAICreated: Bool { origin?.lowercased().hasPrefix(Self.aiOriginPrefix) ?? false }
    /// The AI tool's name, nil when no AI tool wrote it.
    public var proposedBy: String? {
        guard isAICreated, let origin else { return nil }
        return String(origin.dropFirst(Self.aiOriginPrefix.count))
    }

    public func approval(for recipeId: String) -> RecipeApproval? {
        recipes.first { recipeEquals($0.recipeId, recipeId) }
    }
}

/// SHA-256 of file bytes (upstream `RecipeTrustStore.ComputeSha256`).
public enum RecipeHash {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The approvals (upstream `RecipeTrustStore`).
public protocol RecipeTrustStoring: Sendable {
    func record(forFile path: String) -> RecipeTrustRecord?
    /// The approval of the recipe when the record is for exactly this content, else nil.
    func approval(forFile path: String, sha256: String, recipeId: String) -> RecipeApproval?
    /// Keeps the approvals of the file's other recipes for the same content; new content starts a new record.
    func recordApproval(_ approval: RecipeApproval, forFile path: String, sha256: String, content: String?,
                        origin: String?, recipeName: String?, recipeVersion: String?) throws
    /// The record goes when no recipe of it is left.
    func revokeApproval(recipeId: String, forFile path: String) throws
    func revokeAll(forFile path: String) throws
    var allRecords: [RecipeTrustRecord] { get }
}

/// The trust store of the Mac (upstream: DPAPI-encrypted `recipe_trust.dat`): a JSON file (Application Support, RAPP
/// picks the URL) signed with HMAC-SHA256. The key is 32 random bytes in the `SecretStore` (the Keychain in the app)
/// under `keyName`, made on first use. A file whose signature doesn't match, or without a key, counts as empty
/// (default-deny: every recipe asks again) and `wasTampered` says so. A key the secret store fails to read (an error, not
/// a missing key) counts as empty only while it fails: nothing is saved meanwhile, and the key is never replaced. A
/// locked Keychain (`SecretStoreUnavailableError`) is asked again only before a change, not at every look-up (each
/// would show its password prompt); any other error at the next access.
public final class RecipeTrustStore: RecipeTrustStoring, @unchecked Sendable {
    public static let keyName = "recipes.trustStoreKey"

    /// The longest approved content kept in a record, to show the changes later (upstream 256 KB).
    static let maxApprovedContentLength = 256 * 1024

    private let fileURL: URL
    private let secrets: any SecretStore
    private let lock = NSLock()
    private var records: [String: RecipeTrustRecord]?
    private var tampered = false
    /// Why the key couldn't be read the last time the records were read (nil: read, or missing). Changes are refused then
    /// (`recordsToChange`): a save would write an empty store plus the change and drop the approvals of every other file.
    /// The empty records are cached only for `SecretStoreUnavailableError`; after any other error the next access reads
    /// again.
    private var keyReadError: Error?
    /// The records are empty because the store's key wasn't there (deleted) or couldn't be used (a locked Keychain). A
    /// change reads the store once more first: when the key is back, the approvals of the other files are kept; when it
    /// is still missing, the store starts anew as before; when it still can't be used, the change is refused.
    private var readAgainBeforeChange = false

    public init(fileURL: URL, secrets: any SecretStore) {
        self.fileURL = fileURL
        self.secrets = secrets
    }

    public var wasTampered: Bool {
        lock.withLock {
            _ = loadedRecords()
            return tampered
        }
    }

    public func record(forFile path: String) -> RecipeTrustRecord? {
        lock.withLock { loadedRecords()[Self.key(path)] }
    }

    public func approval(forFile path: String, sha256: String, recipeId: String) -> RecipeApproval? {
        guard let record = record(forFile: path), !sha256.isEmpty, recipeEquals(record.sha256, sha256) else { return nil }
        return record.approval(for: recipeId)
    }

    public func recordApproval(_ approval: RecipeApproval, forFile path: String, sha256: String, content: String?,
                               origin: String?, recipeName: String?, recipeVersion: String?) throws {
        guard !path.isEmpty, !sha256.isEmpty else { return }
        try lock.withLock {
            var all = try recordsToChange()
            let key = Self.key(path)
            var record = all[key]
            if record == nil || !recipeEquals(record!.sha256, sha256) {
                record = RecipeTrustRecord(filePath: Self.standardized(path), sha256: sha256.lowercased())
                record?.origin = origin
            }
            guard var updated = record else { return }
            updated.approvedAt = Date()
            updated.recipeName = recipeName ?? updated.recipeName
            updated.recipeVersion = recipeVersion ?? updated.recipeVersion
            updated.origin = origin ?? updated.origin
            if let content, content.utf8.count <= Self.maxApprovedContentLength {
                updated.approvedContent = content
            }
            updated.recipes.removeAll { recipeEquals($0.recipeId, approval.recipeId) }
            updated.recipes.append(approval)
            all[key] = updated
            try save(all)
        }
        log.info("Recorded the approval of recipe '\(approval.recipeId)' in '\(path)' (SHA-256 \(sha256), triggers: \(approval.allTriggers ? "all" : approval.approvedTriggers.joined(separator: ",")), allowed: \(approval.allowedGates.map(\.rawValue).joined(separator: ",")))")
    }

    public func revokeApproval(recipeId: String, forFile path: String) throws {
        try lock.withLock {
            var all = try recordsToChange()
            let key = Self.key(path)
            guard var record = all[key] else { return }
            record.recipes.removeAll { recipeEquals($0.recipeId, recipeId) }
            all[key] = record.recipes.isEmpty ? nil : record
            try save(all)
        }
        log.info("Revoked the approval of recipe '\(recipeId)' in '\(path)'")
    }

    public func revokeAll(forFile path: String) throws {
        try lock.withLock {
            var all = try recordsToChange()
            guard all.removeValue(forKey: Self.key(path)) != nil else { return }
            try save(all)
        }
        log.info("Revoked the approvals of '\(path)'")
    }

    public var allRecords: [RecipeTrustRecord] {
        lock.withLock { loadedRecords().values.sorted { $0.filePath < $1.filePath } }
    }

    // MARK: File

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Paths are compared case-insensitively, like upstream (the Mac's file systems are usually case-insensitive).
    static func key(_ path: String) -> String { standardized(path).lowercased() }

    /// What the file holds: the records as JSON (base64) and their HMAC-SHA256.
    private struct StoreFile: Codable {
        var version = 1
        var records: String
        var signature: String
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Locked.
    private func loadedRecords() -> [String: RecipeTrustRecord] {
        if let records { return records }
        var loaded: [String: RecipeTrustRecord] = [:]
        var cache = true
        defer {
            if cache {
                records = loaded
                keyReadError = nil
            }
        }
        guard let data = try? Data(contentsOf: fileURL) else { return loaded }
        guard let file = try? JSONDecoder().decode(StoreFile.self, from: data),
              let payload = Data(base64Encoded: file.records), let signature = Data(base64Encoded: file.signature) else {
            tampered = true
            log.warn("The recipe trust store can't be read; every recipe file asks for approval again.")
            return loaded
        }
        let key: SymmetricKey?
        do {
            key = try existingKey()
        } catch {
            // Default-deny while it fails, but the store isn't given up: it is read again later.
            if keyReadError == nil {
                log.error("The key of the recipe trust store can't be read; recipe files ask for approval until it can be read again.", error: error)
            }
            keyReadError = error
            cache = false
            if error is SecretStoreUnavailableError {
                // A locked Keychain: reading at every look-up would show its password prompt again and again. The empty
                // records stay until a change, when the user is there to unlock it.
                records = loaded
                readAgainBeforeChange = true
            }
            return loaded
        }
        guard let key, HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: key) else {
            readAgainBeforeChange = key == nil
            tampered = true
            log.warn("The recipe trust store was changed outside Greenshot or its key is gone; every recipe file asks for approval again.")
            return loaded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([RecipeTrustRecord].self, from: payload) else {
            tampered = true
            return loaded
        }
        for record in list where !record.filePath.isEmpty {
            loaded[Self.key(record.filePath)] = record
        }
        return loaded
    }

    /// Locked. The records to change and save, read again when the key was missing or couldn't be used
    /// (`readAgainBeforeChange`); refused while the key can't be read (`keyReadError`): they are empty then, not the
    /// store, and a revocation would be lost.
    private func recordsToChange() throws -> [String: RecipeTrustRecord] {
        if readAgainBeforeChange {
            readAgainBeforeChange = false
            records = nil
        }
        let all = loadedRecords()
        if let keyReadError { throw keyReadError }
        return all
    }

    /// Locked.
    private func save(_ all: [String: RecipeTrustRecord]) throws {
        let list = all.values.sorted { $0.filePath < $1.filePath }
        let payload = try Self.encoder().encode(list)
        let key = try existingKey() ?? newKey()
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        let file = StoreFile(records: payload.base64EncodedString(), signature: signature.base64EncodedString())
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder().encode(file).write(to: fileURL, options: .atomic)
        records = all
        tampered = false
        readAgainBeforeChange = false
    }

    private func existingKey() throws -> SymmetricKey? {
        guard let text = try secrets.secret(for: Self.keyName), let data = Data(base64Encoded: text), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private func newKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try secrets.setSecret(data.base64EncodedString(), for: Self.keyName)
        return key
    }
}

private let log = Log("Recipes")

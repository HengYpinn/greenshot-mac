// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
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

    public func isTriggerApproved(_ key: String) -> Bool { rcoreStub() }
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
    public var proposedBy: String? { rcoreStub() }
    public func approval(for recipeId: String) -> RecipeApproval? { rcoreStub() }
}

/// SHA-256 of file bytes (upstream `RecipeTrustStore.ComputeSha256`).
public enum RecipeHash {
    public static func sha256Hex(_ data: Data) -> String { rcoreStub() }
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
/// (default-deny: every recipe asks again) and `wasTampered` says so.
public final class RecipeTrustStore: RecipeTrustStoring, @unchecked Sendable {
    public static let keyName = "recipes.trustStoreKey"

    public init(fileURL: URL, secrets: any SecretStore) { rcoreStub() }
    public var wasTampered: Bool { rcoreStub() }
    public func record(forFile path: String) -> RecipeTrustRecord? { rcoreStub() }
    public func approval(forFile path: String, sha256: String, recipeId: String) -> RecipeApproval? { rcoreStub() }
    public func recordApproval(_ approval: RecipeApproval, forFile path: String, sha256: String, content: String?,
                               origin: String?, recipeName: String?, recipeVersion: String?) throws { rcoreStub() }
    public func revokeApproval(recipeId: String, forFile path: String) throws { rcoreStub() }
    public func revokeAll(forFile path: String) throws { rcoreStub() }
    public var allRecords: [RecipeTrustRecord] { rcoreStub() }
}

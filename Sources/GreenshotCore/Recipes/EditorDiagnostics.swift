// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a validation message is about, so the editor shows it there.
public enum RecipeDiagnosticTarget: Sendable, Hashable {
    case node(String)
    case trigger(Int)
    case option(String)
    case errorRoutes
    case recipe
}

/// A validation error or warning in the recipe editor (upstream: validation shown against the nodes, docs
/// recipe-contracts-cli-query-plan.md section 6).
public struct RecipeDiagnostic: Sendable, Equatable, Identifiable {
    public var message: String
    public var isError: Bool
    public var target: RecipeDiagnosticTarget
    public var id: String { (isError ? "E:" : "W:") + message }

    public init(message: String, isError: Bool, target: RecipeDiagnosticTarget) {
        self.message = message
        self.isError = isError
        self.target = target
    }
}

/// What a test run may do with the editor's copy of a recipe.
public enum RecipeTestRunDecision: Sendable, Equatable {
    case run
    /// Fix these validation errors first.
    case invalid([String])
    /// The copy needs permissions its approval doesn't give: save it first (saving asks).
    case saveFirst([RecipeGateType])
    /// An automatic step runs inside the recipes it changes.
    case automaticStep
}

/// The recipe editor's validation display, pending bar and test-run rule.
public enum RecipeEditorDiagnostics {
    /// The validator's messages (contract warnings included) with what each is about; the validator's texts are
    /// upstream's and name the step as "Node '<id>'".
    public static func diagnostics(of result: RecipeValidationResult, in recipe: CaptureRecipe) -> [RecipeDiagnostic] {
        result.errors.map { RecipeDiagnostic(message: $0, isError: true, target: target(of: $0, in: recipe)) }
            + result.warnings.map { RecipeDiagnostic(message: $0, isError: false, target: target(of: $0, in: recipe)) }
    }

    public static func target(of message: String, in recipe: CaptureRecipe) -> RecipeDiagnosticTarget {
        func quoted(after prefix: String) -> String? {
            guard let range = message.range(of: prefix) else { return nil }
            let rest = message[range.upperBound...]
            guard let end = rest.firstIndex(of: "'") else { return nil }
            return String(rest[..<end])
        }
        func node(_ id: String?) -> RecipeDiagnosticTarget? {
            guard let id else { return nil }
            if let found = recipe.node(id) { return .node(found.id) }
            if let index = Int(id), recipe.nodes.indices.contains(index), !recipe.nodes[index].id.isEmpty {
                return .node(recipe.nodes[index].id)
            }
            return nil
        }
        if message.hasPrefix("Node '") || message.hasPrefix("Duplicate node id '") || message.hasPrefix("Node id '") {
            return node(quoted(after: "'")) ?? .recipe
        }
        if message.hasPrefix("Error transition") { return .errorRoutes }
        if message.contains("rigger") && message.contains(" at index "), let index = Int(message.components(separatedBy: " at index ")[1]
            .prefix { $0.isNumber }) {
            return .trigger(index)
        }
        if message.hasPrefix("Option key '") { return quoted(after: "Option key '").map(RecipeDiagnosticTarget.option) ?? .recipe }
        if message.hasPrefix("Option '") { return quoted(after: "Option '").map(RecipeDiagnosticTarget.option) ?? .recipe }
        if message.hasPrefix("Duplicate option key '") { return quoted(after: "key '").map(RecipeDiagnosticTarget.option) ?? .recipe }
        // Transitions: the step they come from.
        for prefix in ["(from '", "transition from '", "Transition from '", "source node '", "Cycle/loop detected in recipe flow: "] {
            if prefix.hasSuffix(": "), let range = message.range(of: prefix) {
                let first = message[range.upperBound...].components(separatedBy: " -> ").first ?? ""
                if let found = node(first) { return found }
                continue
            }
            if let found = node(quoted(after: prefix)) { return found }
        }
        return .recipe
    }

    // MARK: Pending bar (upstream UpdateApprovalNotice, RecipeEditorViewModel.cs:622-700)

    /// Unsaved changes: what saving will ask for; nil when it asks nothing (upstream `DescribeSaveDecision`).
    public static func saveNotice(reasons: [String]) -> String? {
        guard !reasons.isEmpty else { return nil }
        let trimmed = reasons.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "." }
        return String(localized: "Saving asks for your approval: \(trimmed.joined(separator: " "))",
                      comment: "Recipe editor banner; the reasons (English, from the approval) follow")
    }

    /// Saved: what is pending for the file's approval (upstream `DescribePendingApproval`); nil when nothing is.
    public static func approvalNotice(details: RecipeDetails?, fileExists: Bool) -> String? {
        guard let details else { return nil }
        if fileExists, !details.isApprovalCurrent {
            return details.approvedHash == nil
                ? String(localized: "This recipe file isn't approved yet. Greenshot asks for your approval before it runs.")
                : String(localized: "This recipe file changed outside Greenshot. Greenshot asks for your approval before it runs.")
        }
        // Name them: "off" alone reads like a bug when the switch was simply left off in the approval.
        let offSuffix = " (off, not approved)"
        let names = details.triggers.filter { $0.label.hasSuffix(offSuffix) }.map { "\"" + String($0.label.dropLast(offSuffix.count)) + "\"" }
        guard !names.isEmpty else { return nil }
        let which = ": " + names.joined(separator: ", ")
        return names.count == 1
            ? String(localized: "1 trigger was left off when this recipe was approved\(which). Review the approval to switch it on.")
            : String(localized: "\(names.count) triggers were left off when this recipe was approved\(which). Review the approval to switch them on.")
    }

    // MARK: Test run

    /// Upstream `ExecuteTestRunAsync` validates first. The Mac also refuses to start a copy whose gated actions (type and
    /// target, like the library's preflight) aren't all covered by the approval it may use: the approved version loaded
    /// from the same file, or the built-in for an unsaved edit of a built-in recipe (`approvedActions`; none otherwise).
    /// The way out is "Save and Run": saving asks for the approval.
    public static func testRunDecision(_ recipe: CaptureRecipe, validation: RecipeValidationResult, isDirty: Bool,
                                       isLoaded: Bool, approvedActions: [RecipeGatedAction]) -> RecipeTestRunDecision {
        if recipe.kind == .extension { return .automaticStep }
        guard validation.isValid else { return .invalid(validation.errors) }
        if !isDirty && isLoaded { return .run }
        let uncovered = validation.gatedActions.filter { !approvedActions.contains($0) }
        guard !uncovered.isEmpty else { return .run }
        return .saveFirst(Array(Set(uncovered.map(\.gateType))).sorted())
    }

    /// The actions an approval allows of an approved version: its gated actions of the allowed types.
    public static func approvedActions(of approved: RecipeValidationResult, approval: RecipeApproval?) -> [RecipeGatedAction] {
        guard let approval else { return [] }
        return approved.gatedActions.filter { approval.isGateAllowed($0.gateType) }
    }
}

/// What saving over an existing file would destroy (the library writes one recipe per file).
public enum RecipeOverwrite: Sendable, Equatable {
    /// No file, or it holds only this recipe.
    case none
    /// It holds other recipes or automatic steps: their names.
    case removes([String])
    /// It exists but isn't a recipe file.
    case notARecipe
}

/// File helpers of the recipe editor.
public enum RecipeEditorFiles {
    /// The path as the library and the trust store keep it (absolute, symbolic links resolved).
    public static func standardized(_ url: URL) -> URL { URL(fileURLWithPath: RecipeTrustStore.standardized(url.path)) }

    /// The recipe file a save panel's choice means: "Capture.json" or "Capture" become "Capture.gsrecipe.json".
    public static func recipeFileURL(for chosen: URL) -> URL {
        let name = chosen.lastPathComponent
        if name.lowercased().hasSuffix(RecipeSerializer.fileExtension) { return chosen }
        let base = name.lowercased().hasSuffix(".json") ? String(name.dropLast(".json".count)) : name
        return chosen.deletingLastPathComponent().appendingPathComponent(base + RecipeSerializer.fileExtension)
    }

    /// What writing `recipe` over a file with `existing` content would remove (nil content: there is no file). `ownIds`:
    /// ids that are this recipe as it was saved there before a rename of its id.
    public static func overwrite(saving recipe: CaptureRecipe, existing: Data?, ownIds: [String] = []) -> RecipeOverwrite {
        guard let existing else { return .none }
        if existing.isEmpty { return .none }
        // JSON that reads as recipes without ids (any other JSON object) isn't a recipe file.
        guard let text = RecipeSerializer.text(of: existing), let inFile = try? RecipeSerializer.decode(text: text),
              inFile.contains(where: { !$0.id.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return .notARecipe
        }
        let others = inFile.filter { item in
            let same = recipeEquals(item.id, recipe.id) && item.kind == recipe.kind
            return !same && !(inFile.count == 1 && ownIds.contains { recipeEquals($0, item.id) })
        }
        return others.isEmpty ? .none : .removes(others.map { $0.name.isEmpty ? $0.id : $0.name })
    }

    /// A file name in `folder` for `id` that isn't taken: "<id>.gsrecipe.json", else "<id> 2.gsrecipe.json", …
    public static func freeFileURL(for id: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let base = id.isEmpty ? "recipe" : id
        var url = folder.appendingPathComponent(base + RecipeSerializer.fileExtension)
        var number = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) \(number)\(RecipeSerializer.fileExtension)")
            number += 1
        }
        return url
    }
}

extension LoadedRecipe {
    /// The file the recipe was loaded from; nil for a built-in recipe.
    public var sourceFile: URL? { fileURL }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What happens with files opened with Greenshot (RCP-069, upstream `IpcSecurityDispatcher.HandleOpenFileAsync`).
public struct RecipeOpenFilePlan: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// No recipe has an OpenFile trigger: the editor opens the files.
        case editor
        /// Recipes have OpenFile triggers, but none is active: nothing opens (upstream's "skipped").
        case skipped
        /// The recipes of the active OpenFile triggers whose filter matches run, each with its file.
        case run
    }

    public struct Run: Sendable, Equatable {
        public var file: URL
        public var trigger: ActiveRecipeTrigger

        public init(file: URL, trigger: ActiveRecipeTrigger) {
            self.file = file
            self.trigger = trigger
        }
    }

    public var kind: Kind
    /// For `.run`: per file, per matching trigger (a file no filter matches has none).
    public var runs: [Run]

    public init(kind: Kind, runs: [Run] = []) {
        self.kind = kind
        self.runs = runs
    }
}

public enum RecipeOpenFileRouting {
    /// Upstream's replies.
    public static let skippedReply = "File opening skipped: all OpenFileTrigger recipes are disabled."
    public static func summary(files: Int, runs: Int) -> String {
        "Opened \(files) file(s) with \(runs) recipe execution(s)."
    }

    /// - Parameters:
    ///   - active: the active OpenFile triggers (`RecipeLibrary.activeTriggers(ofTypes:)`).
    ///   - anyDefined: a recipe has an OpenFile trigger, active or not (`definesOpenFileTrigger`).
    public static func plan(files: [URL], active: [ActiveRecipeTrigger], anyDefined: Bool) -> RecipeOpenFilePlan {
        let triggers = active.filter { $0.trigger.isType(WellKnownTriggerType.openFile) }
        guard !triggers.isEmpty else { return RecipeOpenFilePlan(kind: anyDefined ? .skipped : .editor) }
        var runs: [RecipeOpenFilePlan.Run] = []
        for file in files {
            for trigger in triggers where matches(filter: trigger.trigger.fileFilter, file: file) {
                runs.append(RecipeOpenFilePlan.Run(file: file, trigger: trigger))
            }
        }
        return RecipeOpenFilePlan(kind: .run, runs: runs)
    }

    /// Only the stock "Open file" recipe took the files, each exactly once, and no recipe ran: they open in the editor
    /// as without recipes, with the usual reply (R-F11).
    public static func opensAsBefore(files: [URL], direct: [URL], recipeRuns: Int) -> Bool {
        guard recipeRuns == 0, !files.isEmpty else { return false }
        return files.map(\.path).sorted() == direct.map(\.path).sorted()
    }

    /// Any recipe (switched on or not) has an OpenFile trigger.
    public static func definesOpenFileTrigger(_ recipes: [LoadedRecipe]) -> Bool {
        recipes.contains { $0.recipe.triggers.contains { $0.isType(WellKnownTriggerType.openFile) } }
    }

    /// Upstream: the filter is a list of extensions separated by ';' (".png;.jpg"), compared with the file's extension in
    /// any case; no filter matches every file (the validator requires the dot).
    public static func matches(filter: String?, file: URL) -> Bool {
        let entries = (filter ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !entries.isEmpty else { return true }
        let fileExtension = file.pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }
        return entries.contains { entry in
            let wanted = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry
            return wanted.lowercased() == fileExtension
        }
    }
}

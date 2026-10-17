// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The message after a recipe failed (RCP-018, upstream `CaptureFlowRunner.NotifyFailure` and the exports
/// `ExportNotification.ShowAsync` adds on failure).
public struct RecipeFlowNotice: Sendable, Equatable {
    public var title: String
    public var detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// The flow variable the Notification step keeps: how many exports it announced so far (RSTEPS).
    public static let announcedExportsVariable = "Notification.AnnouncedExports"
    /// Set by the export steps when a destination failed; that destination showed its own error already (RSTEPS).
    public static let exportErrorsVariable = "DestinationExportErrors"

    /// The notice for a finished flow; nil unless it failed, or when a destination already showed the error (upstream
    /// `ExportNotification.FailureShownProperty`).
    public static func failure(of result: RecipeFlowResult) -> RecipeFlowNotice? {
        guard result.state == .failed else { return nil }
        if let shown = result.variables[exportErrorsVariable]?.stringValue, !shown.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }
        let name = result.recipeName.trimmingCharacters(in: .whitespaces).isEmpty ? result.recipeId : result.recipeName
        let reason = [result.reason, result.errorDescription].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Capture flow failed."
        var lines = [reason]
        lines.append(contentsOf: unannouncedExports(of: result).map(describe))
        return RecipeFlowNotice(title: "Recipe “\(name)” failed", detail: lines.joined(separator: "\n"))
    }

    /// The exports no Notification step announced; without the step's count only the failed ones (an export that
    /// worked may have shown its own message).
    static func unannouncedExports(of result: RecipeFlowResult) -> [RecipeExportOutcome] {
        guard let announced = result.variables[announcedExportsVariable]?.doubleValue else {
            return result.exports.filter { !$0.succeeded }
        }
        let count = max(0, min(result.exports.count, Int(announced)))
        return Array(result.exports.dropFirst(count))
    }

    static func describe(_ export: RecipeExportOutcome) -> String {
        let name = RecipeDestinationDesignation(export.designation).displayName
        let target = export.target.map { " (\($0))" } ?? ""
        guard export.succeeded else {
            let error = export.errorMessage.map { ": \($0)" } ?? ""
            return "✗ \(name)\(target)\(error)"
        }
        return "✓ \(name)\(target)"
    }
}

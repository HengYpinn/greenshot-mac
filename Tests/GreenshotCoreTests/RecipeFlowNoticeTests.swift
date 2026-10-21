// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// The message after a recipe failed (RCP-018, upstream `CaptureFlowRunner.NotifyFailure`).
struct RecipeFlowNoticeTests {
    static func result(_ state: RecipeFlowState, reason: String? = nil, variables: [String: JSONValue] = [:],
                       exports: [RecipeExportOutcome] = []) -> RecipeFlowResult {
        RecipeFlowResult(flowId: UUID(), recipeId: "jira", recipeName: "Region to Jira", state: state, reason: reason,
                         variables: RecipeVariables(variables), exports: exports)
    }

    static let saved = RecipeExportOutcome(designation: "FileNoDialog", succeeded: true, target: "~/Shots/a.png")
    static let failed = RecipeExportOutcome(designation: "Clipboard", succeeded: false, errorMessage: "The clipboard is busy")

    @Test func onlyFailedFlowsGetANotice() {
        #expect(RecipeFlowNotice.failure(of: Self.result(.completed)) == nil)
        #expect(RecipeFlowNotice.failure(of: Self.result(.cancelled, reason: "Flow was cancelled.")) == nil)
    }

    @Test func titleAndReason() throws {
        let notice = try #require(RecipeFlowNotice.failure(of: Self.result(.failed, reason: "No window matches 'Safari'")))
        #expect(notice.title == "Recipe “Region to Jira” failed")
        #expect(notice.detail == "No window matches 'Safari'")
    }

    @Test func withoutAReasonUpstreamsText() throws {
        let notice = try #require(RecipeFlowNotice.failure(of: Self.result(.failed, reason: "  ")))
        #expect(notice.detail == "Capture flow failed.")
    }

    @Test func withoutTheCountOnlyFailedExports() throws {
        let notice = try #require(RecipeFlowNotice.failure(of: Self.result(.failed, reason: "Upload failed", exports: [Self.saved, Self.failed])))
        let lines = notice.detail.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines.last?.hasPrefix("✗ ") == true)
        #expect(lines.last?.hasSuffix(": The clipboard is busy") == true)
    }

    @Test func exportsAfterTheAnnouncedOnes() throws {
        let variables: [String: JSONValue] = [RecipeFlowNotice.announcedExportsVariable: .number(1)]
        let notice = try #require(RecipeFlowNotice.failure(of: Self.result(.failed, reason: "Upload failed", variables: variables,
                                                                           exports: [Self.failed, Self.saved])))
        let lines = notice.detail.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines.last?.hasPrefix("✓ ") == true)
        #expect(lines.last?.contains("~/Shots/a.png") == true)
    }

    /// SetVariable can give the count any number (1e30, or 1e999, which a file reads as infinity): it is limited to the
    /// exports there are before it becomes a whole number.
    @Test(arguments: [1e30, .infinity, -.infinity, -5, .nan])
    func anyAnnouncedCountIsLimited(announced: Double) {
        let variables: [String: JSONValue] = [RecipeFlowNotice.announcedExportsVariable: .number(announced)]
        let left = RecipeFlowNotice.unannouncedExports(of: Self.result(.failed, variables: variables, exports: [Self.failed, Self.saved]))
        #expect(left.count == (announced > 0 ? 0 : 2))
    }

    @Test func aDestinationThatShowedItsErrorIsEnough() {
        let variables: [String: JSONValue] = [RecipeFlowNotice.exportErrorsVariable: .string("Jira: unauthorized")]
        #expect(RecipeFlowNotice.failure(of: Self.result(.failed, reason: "Export failed", variables: variables)) == nil)
    }
}

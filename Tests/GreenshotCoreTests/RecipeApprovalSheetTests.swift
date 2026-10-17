// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// The approval window's texts and switches (RCP-193/196/197/201/202, upstream `RecipeApprovalWindow` code-behind).
struct RecipeApprovalSheetTests {
    static let text = """
        {"id": "jira", "name": "Region to Jira",
         "triggers": [{"triggerType": "Hotkey", "parameters": {"Hotkey": "Ctrl + Shift + J"}},
                      {"triggerType": "Clipboard"},
                      {"triggerType": "ContextMenu", "enabled": false}],
         "nodes": [{"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region"}},
                   {"id": "shrink", "stepType": "ExternalCommand", "parameters": {"CommandLine": "/usr/bin/pngquant"}},
                   {"id": "upload", "stepType": "Jira"}],
         "flow": {"startNodes": ["acquire"], "transitions": {"acquire": "shrink", "shrink": "upload"}}}
        """

    static let fileURL = URL(fileURLWithPath: "/tmp/jira.gsrecipe.json")

    static func request(_ mode: RecipeApprovalMode = .newRecipe, text: String = text) throws -> RecipeApprovalRequest {
        let recipe = try #require(try RecipeSerializer.decode(text: text).first)
        var request = RecipeApprovalRequest(mode: mode, recipe: recipe, fileURL: fileURL, content: text,
                                            contentHash: RecipeHash.sha256Hex(Data(text.utf8)))
        let validation = RecipeValidator().validate(recipe)
        request.validation = validation
        let describer = RecipeDescriber()
        request.steps = describer.describeSteps(recipe)
        request.triggers = describer.describeTriggers(recipe)
        request.gates = validation.gateTypes
        return request
    }

    static func record(approved: [String], gates: [RecipeGateType], sha256: String = "old") -> RecipeTrustRecord {
        var record = RecipeTrustRecord(filePath: fileURL.path, sha256: sha256)
        record.recipes = [RecipeApproval(recipeId: "jira", approvedTriggers: approved, allowedGates: gates)]
        return record
    }

    @Test func newFileStartsOnExceptPrograms() throws {
        let sheet = RecipeApprovalSheet(request: try Self.request())
        #expect(sheet.style == .newRecipe)
        #expect(sheet.headerTitle == "External Capture Recipe Detected")
        #expect(sheet.approveTitle == "Approve & Enable")
        #expect(sheet.triggers.map(\.isOn) == [true, true, true])
        let programs = try #require(sheet.gates.first { $0.gate == .externalCommand })
        #expect(!programs.isOn)
        #expect(programs.targets == ["Runs the program /usr/bin/pngquant"])
        let uploads = try #require(sheet.gates.first { $0.gate == .networkAccess })
        #expect(uploads.isOn)
        #expect(!sheet.isApproveEnabled)
    }

    @Test func approveNeedsEveryPermission() throws {
        var sheet = RecipeApprovalSheet(request: try Self.request())
        #expect(sheet.approval(openInEditor: false) == nil)
        sheet.setGate(.externalCommand, on: true)
        #expect(sheet.isApproveEnabled)
        let decision = try #require(sheet.approval(openInEditor: true))
        let approval = try #require(decision.approval)
        #expect(approval.recipeId == "jira")
        #expect(approval.allowedGates.sorted() == [.externalCommand, .networkAccess])
        #expect(approval.approvedTriggers == ["0:Hotkey", "1:Clipboard", "2:ContextMenu"])
        // Only AI proposals offer to open the editor.
        #expect(!decision.openInEditor)
    }

    @Test func leftOffTriggersAreAskedAbout() throws {
        var sheet = RecipeApprovalSheet(request: try Self.request())
        #expect(sheet.leftOffText == nil)
        sheet.setTrigger("1:Clipboard", on: false)
        sheet.setTrigger("2:ContextMenu", on: false)
        // A trigger switched off in the recipe itself isn't one the user leaves off.
        #expect(sheet.leftOffTriggers == ["When an image is copied to the clipboard"])
        let text = try #require(sheet.leftOffText)
        #expect(text.hasPrefix("This trigger stays off"))
    }

    @Test func aiProposalStartsAllOff() throws {
        var request = try Self.request()
        request.proposedBy = "Claude"
        request.aiRequest = "Send it to Jira"
        request.startSwitchedOff = true
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .aiProposal)
        #expect(sheet.badge == "PROPOSED BY AI")
        #expect(sheet.triggers.allSatisfy { !$0.isOn })
        #expect(sheet.gates.allSatisfy { !$0.isOn })
        #expect(sheet.triggerHintIsWarning)
        #expect(sheet.offersOpenInEditor)
        #expect(sheet.aiRequest == "Send it to Jira")
    }

    @Test func aiProposalCanAskToOpenTheEditor() throws {
        var request = try Self.request()
        request.proposedBy = "Claude"
        var sheet = RecipeApprovalSheet(request: request)
        sheet.setGate(.externalCommand, on: true)
        sheet.setGate(.networkAccess, on: true)
        let decision = try #require(sheet.approval(openInEditor: true))
        #expect(decision.openInEditor)
    }

    @Test func aChangedAIFileIsNoProposal() throws {
        var request = try Self.request(.modified)
        request.proposedBy = "Claude"
        request.startSwitchedOff = true
        request.previousRecord = Self.record(approved: ["0:Hotkey"], gates: [.networkAccess])
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .modified)
        #expect(sheet.proposedBy == "Claude")
        #expect(sheet.triggers.allSatisfy { !$0.isOn })
    }

    @Test func reviewKeepsTheSwitchesAndRevokes() throws {
        var request = try Self.request(.reVerify)
        request.previousRecord = Self.record(approved: ["0:Hotkey"], gates: [.externalCommand, .networkAccess])
        request.suggestedApproval = request.previousRecord?.approval(for: "jira")
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .review)
        #expect(sheet.isReview)
        #expect(sheet.rejectTitle == "Revoke Approval")
        #expect(sheet.approveTitle == "Save Changes")
        #expect(sheet.triggers.map(\.isOn) == [true, false, false])
        #expect(sheet.gates.allSatisfy { $0.isOn })
        #expect(sheet.previousHash == "old")
        #expect(sheet.revokeText.contains("Region to Jira"))
    }

    @Test func modifiedFileStartsTriggersOnAgain() throws {
        var request = try Self.request(.modified)
        request.previousRecord = Self.record(approved: [], gates: [])
        request.previousContent = "{}"
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .modified)
        #expect(sheet.triggers.map(\.isOn) == [true, true, true])
        #expect(sheet.changesTitle == "What changed since the last approval")
        #expect(sheet.changeLines == ["No change in what the recipe does (only details like names or layout)."])
    }

    @Test func ownEditKeepsAllowedPermissions() throws {
        var request = try Self.request(.modified)
        request.ownEditReasons = ["It needs external commands."]
        request.suggestedApproval = RecipeApproval(recipeId: "jira", approvedTriggers: ["0:Hotkey"], allowedGates: [.networkAccess])
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .ownEdit)
        #expect(sheet.headerDescription.hasSuffix("It needs external commands."))
        #expect(sheet.triggers.map(\.isOn) == [true, false, false])
        let uploads = try #require(sheet.gates.first { $0.gate == .networkAccess })
        #expect(uploads.isOn)
        let programs = try #require(sheet.gates.first { $0.gate == .externalCommand })
        #expect(!programs.isOn)
    }

    @Test func replacingABuiltInSaysSo() throws {
        var request = try Self.request()
        request.replacesBuiltIn = true
        request.replacedRecipe = CaptureRecipe(id: "jira", name: "Capture region")
        request.previousContent = "{}"
        request.changes = ["Adds: Uploads to Jira"]
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.changesTitle == "Replaces the built-in recipe “Capture region”")
        #expect(sheet.changeLines == ["Adds: Uploads to Jira"])
    }

    @Test func detailsAreReadOnly() throws {
        var request = try Self.request(.reVerify)
        request.isReadOnly = true
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .details)
        #expect(!sheet.isDecision)
        #expect(sheet.approval(openInEditor: false) == nil)
        #expect(sheet.badge == "APPROVED")
    }

    @Test func builtInDetailsHaveEveryPermission() throws {
        var request = try Self.request(.reVerify)
        request.fileURL = nil
        request.isReadOnly = true
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.badge == "BUILT-IN")
        #expect(sheet.fileText == "Built into Greenshot")
        #expect(sheet.gates.allSatisfy { $0.isOn })
    }

    @Test func validationErrorListsProblemsWithHints() throws {
        let broken = """
            {"id": "x", "name": "X", "nodes": [{"id": "a", "stepType": "Nope"}], "flow": {"startNodes": ["a"]}}
            """
        var request = try Self.request(.validationError, text: broken)
        request.errorMessage = "ignored when the validation has errors"
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.style == .validationError)
        #expect(sheet.approveTitle == "Close")
        #expect(sheet.triggers.isEmpty)
        #expect(sheet.gates.isEmpty)
        let problem = try #require(sheet.problems.first)
        #expect(problem.message.contains("'Nope'"))
        #expect(problem.hint != nil)
    }

    @Test func unreadableFileShowsTheMessage() {
        var request = RecipeApprovalRequest(mode: .validationError, recipe: nil, fileURL: Self.fileURL, content: "{", contentHash: "abc")
        request.errorMessage = "The recipe file is not valid JSON: unexpected end"
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.recipeName == "jira.gsrecipe.json")
        #expect(sheet.problems.count == 1)
        #expect(sheet.problems.first?.hint == "Check the recipe JSON syntax for unescaped quotes, trailing commas, or mismatched brackets.")
    }

    @Test func automaticStepTexts() throws {
        var request = try Self.request()
        request.recipe?.kind = .extension
        request.extensionReach = ["Changes these recipes now: Capture region"]
        let sheet = RecipeApprovalSheet(request: request)
        #expect(sheet.isExtension)
        #expect(sheet.headerTitle == "Automatic Step File Detected")
        #expect(sheet.badge == "NEW AUTOMATIC STEP")
        #expect(sheet.triggers.isEmpty)
        #expect(sheet.extensionReach.count == 1)
    }

    @Test func hintsForTheMacsMessages() {
        #expect(RecipeValidationHints.hint(for: "Duplicate node id 'a' found in recipe.") == "Each node in the recipe must have a unique 'id'.")
        #expect(RecipeValidationHints.hint(for: "Cycle/loop detected in recipe flow: a -> b -> a") != nil)
        #expect(RecipeValidationHints.hint(for: "Something else entirely") == nil)
    }
}

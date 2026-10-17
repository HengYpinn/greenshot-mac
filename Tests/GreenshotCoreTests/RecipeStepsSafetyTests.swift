// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// What the wave 4 reviews asked of the app steps: the question before a command-line run captures without the user
/// (SM-M1), files that stay in their folder (S-M1), the destination names the automatic steps know (R-F4).
@Suite struct RecipeStepsSafetyTests {
    // MARK: Does the user select before the capture goes anywhere?

    func recipe(_ nodes: [RecipeNode], _ transitions: [(String, String)]) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "safety", name: "Safety")
        recipe.nodes = nodes
        recipe.flow.startNodes = nodes.first.map { [$0.id] } ?? []
        for (from, to) in transitions { recipe.flow.addTransition(from: from, to: to) }
        return recipe
    }

    func node(_ id: String, _ type: String) -> RecipeNode { RecipeNode(id: id, stepType: type) }

    @Test func aSelectionOnEveryWay() {
        let selected = recipe([node("acquire", "Source"), node("select", "InteractiveSelection"), node("export", "Destinations")],
                              [("acquire", "select"), ("select", "export")])
        #expect(RecipeSourceValues.selectionFollows(selected, from: "acquire"))
        let none = recipe([node("acquire", "Source"), node("export", "Destinations")], [("acquire", "export")])
        #expect(!RecipeSourceValues.selectionFollows(none, from: "acquire"))
        let ends = recipe([node("acquire", "Source")], [])
        #expect(!RecipeSourceValues.selectionFollows(ends, from: "acquire"))
    }

    @Test func oneWayWithoutASelectionIsEnough() {
        var branching = recipe([node("acquire", "Source"), node("check", "Conditional"), node("select", "InteractiveSelection"),
                                node("export", "Destinations")],
                               [("acquire", "check"), ("select", "export")])
        branching.flow.conditionalTransitions = [ConditionalTransition(from: "check", branch: "ask", to: "select"),
                                                 ConditionalTransition(from: "check", branch: "else", to: "export")]
        #expect(!RecipeSourceValues.selectionFollows(branching, from: "acquire"))
        // Two ways that meet again before the selection: both select.
        let diamond = recipe([node("acquire", "Source"), node("a", "Effect"), node("b", "Effect"), node("join", "Effect"),
                              node("select", "InteractiveSelection")],
                             [("acquire", "a"), ("acquire", "b"), ("a", "join"), ("b", "join"), ("join", "select")])
        #expect(RecipeSourceValues.selectionFollows(diamond, from: "acquire"))
    }

    @Test func aSelectionThatMayNotRunDoesntCount() {
        var off = node("select", "InteractiveSelection")
        off.enabled = .expression("${option.ask}")
        let maybe = recipe([node("acquire", "Source"), off, node("export", "Destinations")], [("acquire", "select"), ("select", "export")])
        #expect(!RecipeSourceValues.selectionFollows(maybe, from: "acquire"))
        // An error route to another recipe takes the capture along.
        var forwarding = recipe([node("acquire", "Source"), node("effect", "Effect"), node("select", "InteractiveSelection")],
                                [("acquire", "effect"), ("effect", "select")])
        forwarding.flow.errorTransitions = [ErrorTransition(from: "effect", targetRecipeId: "uploader")]
        #expect(!RecipeSourceValues.selectionFollows(forwarding, from: "acquire"))
        // A loop back without a selection.
        let loop = recipe([node("acquire", "Source"), node("a", "Effect"), node("b", "Effect")], [("acquire", "a"), ("a", "b"), ("b", "a")])
        #expect(!RecipeSourceValues.selectionFollows(loop, from: "acquire"))
    }

    @Test func theBuiltInsSelect() {
        #expect(RecipeSourceValues.selectionFollows(BuiltInRecipes.region, from: "acquire"))
        #expect(RecipeSourceValues.selectionFollows(BuiltInRecipes.ocr, from: "acquire"))
        #expect(!RecipeSourceValues.selectionFollows(BuiltInRecipes.aiCaptureRegion, from: "acquire"))
    }

    @Test func whatIsAskedFor() {
        #expect(RecipeSourceValues.unattendedSubject(.fullScreen, region: false, named: false, selectionFollows: true)
                == "a screenshot of the whole screen")
        #expect(RecipeSourceValues.unattendedSubject(.region, region: true, named: false, selectionFollows: true) == "a screenshot of a region")
        #expect(RecipeSourceValues.unattendedSubject(.region, region: false, named: false, selectionFollows: true) == nil)
        #expect(RecipeSourceValues.unattendedSubject(.textOcr, region: false, named: false, selectionFollows: false)
                == "a screenshot of the whole screen")
        #expect(RecipeSourceValues.unattendedSubject(.window, region: false, named: true, selectionFollows: true) == "a screenshot of a window")
        #expect(RecipeSourceValues.unattendedSubject(.window, region: false, named: false, selectionFollows: true) == nil)
        #expect(RecipeSourceValues.unattendedSubject(.activeWindow, region: false, named: false, selectionFollows: true)
                == "a screenshot of the active window")
        #expect(RecipeSourceValues.unattendedSubject(.lastRegion, region: false, named: false, selectionFollows: false)
                == "a screenshot of the last captured region")
        #expect(RecipeSourceValues.unattendedSubject(.clipboard, region: false, named: false, selectionFollows: false) == nil)
        #expect(RecipeSourceValues.unattendedSubject(.file, region: false, named: false, selectionFollows: false) == nil)
    }

    final class Questions: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var all: [String] { lock.withLock { asked } }
        func add(_ subject: String) { lock.withLock { asked.append(subject) } }
    }

    @Test func theQuestionComesOncePerSubject() async {
        let questions = Questions()
        let consent = RecipeCaptureConsent(granted: ["a screen recording"]) { subject in
            questions.add(subject)
            return subject != "a screenshot of the active window"
        }
        #expect(await consent.allows("a screen recording"))
        #expect(await consent.allows("a screenshot of the whole screen"))
        #expect(await consent.allows("a screenshot of the whole screen"))
        #expect(!(await consent.allows("a screenshot of the active window")))
        #expect(!(await consent.allows("a screenshot of the active window")))
        #expect(questions.all == ["a screenshot of the whole screen", "a screenshot of the active window", "a screenshot of the active window"])
    }

    // MARK: Files stay in their folder (S-M1)

    @Test func filesInsideTheirFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/Pictures/Greenshot")
        #expect(RecipeFileExportOptions.isInside(folder.appendingPathComponent("2026/shot.png"), folder: folder))
        #expect(!RecipeFileExportOptions.isInside(folder.appendingPathComponent("../../Library/x.png"), folder: folder))
        #expect(!RecipeFileExportOptions.isInside(folder.appendingPathComponent("a/../../b.png"), folder: folder))
        #expect(!RecipeFileExportOptions.isInside(folder, folder: folder))
        #expect(!RecipeFileExportOptions.isInside(URL(fileURLWithPath: "/Users/me/Pictures/GreenshotOther/x.png"), folder: folder))
        #expect(RecipeFileExportOptions.isAbsolutePattern("/Volumes/Shots/${title}"))
        #expect(RecipeFileExportOptions.isAbsolutePattern(" ~/Desktop/${title}"))
        #expect(!RecipeFileExportOptions.isAbsolutePattern("${title}/../x"))
    }

    // MARK: Destination names (R-F4)

    @Test func aliasesAsTheirDestinationsOwnName() {
        let commands = ["Preview"]
        for (alias, canonical) in [("File", "FileNoDialog"), ("SaveFile", "FileNoDialog"), ("Mail", "EMail"), ("Share", "Windows10Share"),
                                   ("OCR", "Windows10OCR"), ("QRCode", "ZxingQrDestination"), ("Notes", "OneNote"), ("clipboard", "Clipboard"),
                                   ("External", "External Preview"), ("external preview", "External Preview"), ("Nowhere", "Nowhere")] {
            #expect(RecipeDestinationPlan.canonicalDesignation(alias, commands: commands) == canonical, "\(alias)")
        }
        // The automatic step stored for "EMail" now runs for a recipe that says "Mail".
        var flow = CaptureRecipe(id: "safety", name: "Safety")
        flow.nodes = [RecipeNode(id: "x", stepType: "Effect")]
        let chain = RecipeDestinationChain(extensionId: "ext_mail", flow: flow, onlyDestinations: ["EMail"])
        #expect(chain.runs(for: RecipeDestinationPlan.canonicalDesignation("Mail", commands: [])))
    }
}

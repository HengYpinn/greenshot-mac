// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Security review of the recipe engine: a tampered file keeps no approval of its own, error handlers can't loop forever,
/// the approval sheet names the Clipboard trigger as it is, and a file name from a value stays in the output folder.
@MainActor
@Suite struct RecipeSecurityFixesTests {
    // MARK: R2: saving a file that isn't the approved one asks about each new target

    @Test func savingATamperedFileAsksAboutItsNewCommand() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let harmless = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/usr/bin/true")])
        let url = try fixture.write(libraryRecipe(extraNode: harmless))
        _ = await fixture.library.loadFile(url)
        let approved = try #require(fixture.library.recipe(id: "lib_recipe")).recipe

        // The same kind of edit in the approved file stays quiet, as before.
        var edited = approved
        edited.name = "Renamed"
        #expect(fixture.library.saveDecisionReasons(for: edited, at: url).isEmpty)

        // The file changes behind Greenshot's back: another command, same kind.
        let rm = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/bin/rm")])
        let tampered = libraryRecipe(extraNode: rm)
        _ = try fixture.write(tampered)
        let reasons = fixture.library.saveDecisionReasons(for: tampered, at: url)
        #expect(reasons.contains("Runs the program /bin/rm"))

        let requestsBefore = fixture.approver.requests.count
        fixture.approver.answer = { _ in nil }
        let saved = await fixture.library.save(tampered, to: url)
        #expect(!saved.errors.isEmpty)
        #expect(fixture.approver.requests.count == requestsBefore + 1)
        let request = try #require(fixture.approver.requests.last)
        #expect(request.ownEditReasons?.contains("Runs the program /bin/rm") == true)
    }

    // MARK: R4: error handlers can't loop

    @Test func theValidatorRefusesAnErrorEdgeThatLoops() {
        var own = testRecipe([RecipeNode(id: "s", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard")])
        own.nodes[0].onErrorNodeId = "s"
        let ownResult = RecipeValidator().validate(own)
        #expect(ownResult.errors.contains { $0.hasPrefix("Cycle/loop detected") })

        var pair = testRecipe([RecipeNode(id: "s", stepType: "Source"), RecipeNode(id: "h1", stepType: "Clipboard"),
                               RecipeNode(id: "h2", stepType: "Clipboard")], transitions: [("s", ["h1"])])
        pair.flow.errorTransitions = [ErrorTransition(from: "h1", to: "h2"), ErrorTransition(from: "h2", to: "h1")]
        let pairResult = RecipeValidator().validate(pair)
        #expect(pairResult.errors.contains { $0.hasPrefix("Cycle/loop detected") })
    }

    @Test func aWildcardErrorHandlerIsNotALoop() {
        var recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard"),
                                 RecipeNode(id: "handler", stepType: "Clipboard")])
        recipe.flow.errorTransitions = [ErrorTransition(from: "*", to: "handler")]
        let result = RecipeValidator().validate(recipe)
        #expect(!result.errors.contains { $0.hasPrefix("Cycle/loop detected") })
    }

    @Test func aNodeThatRoutesItsErrorToItselfStopsAtTheCap() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { _, _ in throw RecipeStepError("Boom") }
        var recipe = RecipeEngineHarness.recipe(["s"], start: ["s"], [])
        recipe.nodes[0].onErrorNodeId = "s"
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(context.isAborted)
        #expect(context.abortReason?.contains("error handlers in one run") == true)
        // The first run plus one run per allowed handler.
        #expect(recorder.all.count == RecipeErrorHopCounter.maxHops + 1)
    }

    @Test func recipesThatForwardTheirErrorsToEachOtherStopAtTheCap() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { _, _ in throw RecipeStepError("Boom") }
        var first = RecipeEngineHarness.recipe(["x"], start: ["x"], [])
        first.id = "first"
        first.nodes[0].onErrorRecipeId = "second"
        var second = RecipeEngineHarness.recipe(["y"], start: ["y"], [])
        second.id = "second"
        second.nodes[0].onErrorRecipeId = "first"
        let (loopFirst, loopSecond) = (first, second)
        let context = await RecipeEngineHarness.run(first, registry) { id in id == "second" ? loopSecond : loopFirst }
        #expect(context.isAborted || context.state == .failed)
        #expect(recorder.all.count <= RecipeErrorHopCounter.maxForwardDepth + 1)
        #expect(context.abortReason?.contains("forwarding through") == true)
    }

    // MARK: R5: the Clipboard trigger is described as it fires

    @Test func theClipboardTriggerIsDescribedAsItFires() {
        func label(_ parameters: JSONObject) -> String {
            var recipe = CaptureRecipe(id: "clip", name: "Clip")
            recipe.triggers = [TriggerConfig(triggerType: "Clipboard", parameters: parameters)]
            return RecipeDescriber().describeTriggers(recipe).first?.label ?? ""
        }
        #expect(label([:]) == "When an image is copied to the clipboard")
        #expect(label(["OnImageCopied": .bool(false)]) == "When anything is copied to the clipboard")
        #expect(label(["OnImageCopied": .bool(false), "FormatFilter": .string("text")])
                == "When something in the format \"text\" is copied to the clipboard")
    }

    // MARK: R3: a value can't send the file out of the folder

    @Test func aValueWithALeadingSlashOrTildeStaysInTheFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/Pictures/Greenshot", isDirectory: true)
        let relative = RecipeNode(id: "save", stepType: "Destinations", parameters: ["FilenamePattern": .string("${Barcode.Text}")])
        // The evaluated text is what the step sees; the raw parameter is what the author wrote.
        let step = RecipeStepInvocation(node: relative, parameters: ["FilenamePattern": .string("/tmp/x")], contract: nil)
        #expect(!RecipeFileTarget.rawPatternIsAbsolute(step))
        for value in ["/tmp/x", "~/Pictures/family", "//tmp/x"] {
            let file = RecipeFileTarget.file(forName: value, rawPattern: "${Barcode.Text}", in: folder, fileExtension: "png")
            #expect(RecipeFileExportOptions.isInside(file, folder: folder), "\(value) -> \(file.path)")
        }
        let climbing = RecipeFileTarget.file(forName: "../../x", rawPattern: "${Barcode.Text}", in: folder, fileExtension: "png")
        #expect(RecipeFileExportOptions.isInside(climbing, folder: folder))
    }

    @Test func anAbsolutePatternWrittenByTheAuthorStillWorks() {
        let folder = URL(fileURLWithPath: "/Users/me/Pictures/Greenshot", isDirectory: true)
        let absolute = RecipeNode(id: "save", stepType: "Destinations", parameters: ["FilenamePattern": .string("/Volumes/Shots/${title}")])
        let step = RecipeStepInvocation(node: absolute, parameters: ["FilenamePattern": .string("/Volumes/Shots/a")], contract: nil)
        #expect(RecipeFileTarget.rawPatternIsAbsolute(step))
        let file = RecipeFileTarget.file(forName: "/Volumes/Shots/a", rawPattern: "/Volumes/Shots/${title}", in: folder, fileExtension: "png")
        #expect(file.path == "/Volumes/Shots/a.png")
    }

    // MARK: Rework: the bytes the editor loaded count, not the file at save time

    @Test func aRestoredOrDeletedFileDoesntRestoreTheApproval() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let harmless = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/usr/bin/true")])
        let approvedRecipe = libraryRecipe(extraNode: harmless)
        let url = try fixture.write(approvedRecipe)
        _ = await fixture.library.loadFile(url)
        let approvedBytes = try Data(contentsOf: url)

        // The editor loaded the tampered bytes; the attacker puts the approved bytes back before the save.
        let rm = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/bin/rm")])
        let tampered = libraryRecipe(extraNode: rm)
        let tamperedBytes = Data(RecipeSerializer.encode(tampered).utf8)
        try approvedBytes.write(to: url)
        let loaded = RecipeHash.sha256Hex(tamperedBytes)
        let reasons = fixture.library.saveDecisionReasons(for: tampered, at: url, loadedSha256: loaded)
        #expect(reasons.contains("Runs the program /bin/rm"))
        fixture.approver.answer = { _ in nil }
        let before = fixture.approver.requests.count
        let saved = await fixture.library.save(tampered, to: url, loadedSha256: loaded)
        #expect(!saved.errors.isEmpty)
        #expect(fixture.approver.requests.count == before + 1)

        // Editor bytes that are the approved ones: no question.
        let approvedHash = RecipeHash.sha256Hex(approvedBytes)
        #expect(fixture.library.saveDecisionReasons(for: approvedRecipe, at: url, loadedSha256: approvedHash).isEmpty)

        // Without the editor's hash, a deleted file counts as changed.
        try FileManager.default.removeItem(at: url)
        let afterDelete = fixture.library.saveDecisionReasons(for: tampered, at: url)
        #expect(afterDelete.contains("Runs the program /bin/rm"))
    }

    // MARK: Rework: wildcard error handlers

    @Test func wildcardErrorHandlersAreValid() {
        var withSuccessor = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard"),
                                        RecipeNode(id: "handler", stepType: "Clipboard"), RecipeNode(id: "notify", stepType: "Clipboard")],
                                       transitions: [("a", ["b"]), ("handler", ["notify"])])
        withSuccessor.flow.errorTransitions = [ErrorTransition(from: "*", to: "handler")]
        let first = RecipeValidator().validate(withSuccessor)
        #expect(!first.errors.contains { $0.hasPrefix("Cycle/loop detected") })

        var two = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "other", stepType: "Clipboard"),
                              RecipeNode(id: "handler", stepType: "Clipboard")], transitions: [("a", ["other"])])
        two.flow.errorTransitions = [ErrorTransition(from: "*", to: "other", errorType: "OtherException"), ErrorTransition(from: "*", to: "handler")]
        let second = RecipeValidator().validate(two)
        #expect(!second.errors.contains { $0.hasPrefix("Cycle/loop detected") })
    }

    // MARK: Rework: absolute patterns keep to their fixed start

    @Test func anAbsoluteRawPatternKeepsValuesInsideItsRoot() {
        let folder = URL(fileURLWithPath: "/Users/me/Pictures/Greenshot", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let raw = "/tmp/shots/${X}"
        let climbing = RecipeFileTarget.file(forName: "/tmp/shots/../../etc/x", rawPattern: raw, in: folder, fileExtension: "png", home: home)
        #expect(FilenamePattern.isInside(climbing, folder: URL(fileURLWithPath: "/tmp/shots", isDirectory: true)))
        let fine = RecipeFileTarget.file(forName: "/tmp/shots/a", rawPattern: raw, in: folder, fileExtension: "png", home: home)
        #expect(fine.path == "/tmp/shots/a.png")
        let tilde = RecipeFileTarget.file(forName: "~/Pictures/../../x", rawPattern: "~/Pictures/${X}", in: folder, fileExtension: "png", home: home)
        #expect(FilenamePattern.isInside(tilde, folder: home.appendingPathComponent("Pictures", isDirectory: true)))
    }

    @Test func aRecordedVideoPathFromAValueStaysInItsFolder() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let defaultFolder = home.appendingPathComponent("Movies/Greenshot", isDirectory: true)
        func url(_ path: String, raw: String) -> URL {
            RecordingOutputPath.recipeURL(outputFilePath: path, rawOutputFilePath: raw, outputDirectory: nil, filenamePattern: nil,
                                          date: Date(), environment: [:], homeDirectory: home)
        }
        // A relative raw path: a value with "..", "/" or "~" stays in the default folder.
        for value in ["../../x.mp4", "/etc/x.mp4", "~/x.mp4"] {
            let file = url(value, raw: "${Barcode.Text}")
            #expect(FilenamePattern.isInside(file, folder: defaultFolder), "\(value) -> \(file.path)")
        }
        // An absolute raw path: values stay inside its fixed start.
        let inside = url("/tmp/clips/a.mp4", raw: "/tmp/clips/${X}")
        #expect(inside.path == "/tmp/clips/a.mp4")
        let climbing = url("/tmp/clips/../../etc/x.mp4", raw: "/tmp/clips/${X}")
        #expect(FilenamePattern.isInside(climbing, folder: URL(fileURLWithPath: "/tmp/clips", isDirectory: true)))
        // The author's own absolute path works.
        let own = url("/Volumes/Clips/x.mp4", raw: "/Volumes/Clips/x.mp4")
        #expect(own.path == "/Volumes/Clips/x.mp4")
    }
}

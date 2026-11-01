// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Security review: a gated value that is decided when the recipe runs (an expression, or a variable the recipe can set)
/// still needs its permission, and the approval says it is decided at run time.
@MainActor
@Suite struct RecipeGateTests {
    func gates(_ node: RecipeNode, _ environment: GateEnvironment = .empty) -> [RecipeGatedAction] {
        StepContractCatalog.builtIn.contract(for: node.stepType)?.gates(node, environment) ?? []
    }

    func node(_ type: String, _ parameters: JSONObject) -> RecipeNode {
        RecipeNode(id: "n", stepType: type, parameters: parameters)
    }

    func details(_ recipe: CaptureRecipe) -> [String] {
        RecipeDescriber().describeSteps(recipe).map(\.text)
    }

    @Test func aSourceFileFromAnArgumentStillNeedsFileAccess() {
        let fromArgument = node("Source", ["SourceType": .string("File"), "Filename": .string("${Arg}")])
        let expected = RecipeGatedAction(.fileSystemAccess, target: "Reads an image file named when the recipe runs (${Arg})")
        #expect(gates(fromArgument) == [expected])
        let lines = details(testRecipe([fromArgument]))
        #expect(lines.contains("Loads an image file named when the recipe runs (${Arg})"))
        #expect(lines.contains("Reads an image file named when the recipe runs (${Arg})"))
        // Upstream parses the source type with Enum.TryParse, which takes numbers: only known names skip the gate.
        let numbered = gates(node("Source", ["SourceType": .string("6")]))
        #expect(numbered.map(\.gateType) == [.fileSystemAccess])
        let decided = gates(node("Source", ["SourceType": .string("${Kind}")]))
        #expect(decided == [RecipeGatedAction(.fileSystemAccess,
                                              target: "May read an image file (the source type is decided when the recipe runs (${Kind}))")])
        #expect(gates(node("Source", ["SourceType": .string("Region")])).isEmpty)
        #expect(gates(node("Source", [:])).isEmpty)
        let literal = gates(node("Source", ["SourceType": .string("file"), "Filename": .string("/tmp/a.png")]))
        #expect(literal == [RecipeGatedAction(.fileSystemAccess, target: "Reads the image file /tmp/a.png")])
    }

    @Test func aCommandFromAnArgumentIsNotShownAsAProgram() {
        let fromArgument = node("ExternalCommand", ["CommandLine": .string("${Arg}")])
        let action = RecipeGatedAction(.externalCommand, target: "a command given when the recipe runs (${Arg})")
        #expect(gates(fromArgument) == [action])
        #expect(RecipeDescriber().describe(action) == "Runs a command given when the recipe runs (${Arg})")
        #expect(details(testRecipe([fromArgument])).contains("Runs a command given when the recipe runs (${Arg})"))
        let named = gates(node("ExternalCommand", ["Command": .string("${option.tool}")]))
        #expect(named.first?.target == "a command given when the recipe runs (${option.tool})")
        let arguments = gates(node("ExternalCommand", ["CommandLine": .string("/bin/sh"), "Arguments": .string("-c ${Arg}")]))
        #expect(arguments.first?.target == "/bin/sh with arguments given when the recipe runs (-c ${Arg})")
        // Literal commands read as before.
        let configured = GateEnvironment(commandLine: { $0 == "Optimize" ? "/usr/local/bin/pngquant" : nil })
        let optimize = gates(node("ExternalCommand", ["Command": .string("Optimize")]), configured)
        #expect(optimize.first?.target == "Optimize (/usr/local/bin/pngquant)")
        #expect(RecipeDescriber().describe(optimize[0]) == "Runs the program Optimize (/usr/local/bin/pngquant)")
    }

    @Test func destinationsDecidedAtRunTimeNeedEveryPermission() {
        let decided = node("Destinations", ["DestinationDesignations": .array([.string("${Dest}")])])
        let types = Set(gates(decided).map(\.gateType))
        #expect(types == [.externalCommand, .networkAccess])
        #expect(details(testRecipe([decided])).contains("Sends the result to a destination decided when the recipe runs (${Dest})"))
        let custom = gates(node("CustomDestination", ["CustomDestinationId": .string("External ${Name}")]))
        #expect(Set(custom.map(\.gateType)) == [.externalCommand, .networkAccess])
        let folder = gates(node("SaveFile", ["SaveDirectory": .string("${Dir}")]))
        #expect(folder == [RecipeGatedAction(.fileSystemAccess, target: "Writes files to a folder decided when the recipe runs (${Dir})")])
        #expect(gates(node("Destinations", ["DestinationDesignations": .array([.string("Clipboard")])])).isEmpty)
        let video = gates(node("RecordVideo", ["OutputDirectory": .string("${Dir}")]))
        #expect(video.first?.target == "Writes the video to a place decided when the recipe runs (${Dir})")
    }

    /// The plain "External" (the settings' external command, what `designation(for: .externalCommand)` gives) is an
    /// external command too and needs its permission, as upstream.
    @Test func plainExternalIsAnExternalCommand() {
        let designation = RecipeDestinationDesignation("External")
        #expect(designation.destination == .externalCommand)
        #expect(designation.externalCommandName == nil)
        let plain = gates(node("Destinations", ["DestinationDesignations": .array([.string("External")])]))
        #expect(plain == [RecipeGatedAction(.externalCommand, target: "External")])
        let named = RecipeDestinationDesignation(RecipeDestinationDesignation.designation(for: .externalCommand))
        #expect(named.destination == .externalCommand)
    }

    @Test func overrideDestinationsSetByTheRecipe() {
        let nodes = [RecipeNode(id: "a", stepType: "Source"), node("Destinations", ["DestinationDesignations": .array([.string("Clipboard")])])]
        var plain = testRecipe(nodes, transitions: [("a", ["n"])])
        #expect(RecipeValidator().validate(plain).gateTypes.isEmpty)
        var fromArgument = plain
        fromArgument.triggers = [TriggerConfig(triggerType: "Commandline", parameters: [
            "Command": .string("send"),
            "Arguments": .array([.object(["name": .string("to"), "variable": .string("OverrideDestinations")])])
        ])]
        let bound = RecipeValidator().validate(fromArgument)
        #expect(bound.gateTypes == [.externalCommand, .networkAccess])
        #expect(details(fromArgument).contains("Runs a command chosen when the recipe runs (the variable OverrideDestinations)"))
        // The destination aliases read OverrideDestinations too (upstream registers DestinationExportStep under them).
        var clipboard = fromArgument
        clipboard.nodes[1] = RecipeNode(id: "n", stepType: "Clipboard")
        #expect(RecipeValidator().validate(clipboard).gateTypes == [.externalCommand, .networkAccess])
        plain.nodes.insert(node("SetVariable", ["Variable": .string("OverrideDestinations"), "Value": .string("${Arg}")]), at: 0)
        plain.nodes[0].id = "set"
        plain.flow.startNodes = ["set"]
        plain.flow.addTransition(from: "set", to: "a")
        #expect(RecipeValidator().validate(plain).gateTypes == [.externalCommand, .networkAccess])
    }

    /// RECIPES-1: an absolute `FilenamePattern` of the recipe's author writes (and with the default setting replaces) files
    /// outside the output folder, so it needs file system access and the step line says where.
    @Test func anAbsoluteFilenamePatternNeedsFileAccess() {
        let save = node("SaveFile", ["FilenamePattern": .string("~/Pictures/x"), "AllowOverwrite": .bool(true)])
        let expected = RecipeGatedAction(.fileSystemAccess, target: "Writes files to ~/Pictures/x and may replace existing files there")
        #expect(gates(save) == [expected])
        let recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "SaveFile", parameters: save.parameters)])
        let validation = RecipeValidator().validate(recipe)
        #expect(validation.gateTypes == [.fileSystemAccess])
        let lines = details(recipe)
        #expect(lines.contains("Saves the result to ~/Pictures/x"))
        #expect(lines.contains("Writes files to ~/Pictures/x and may replace existing files there"))
        // The same parameters on a Destinations step, and a pattern without a fixed start.
        let listed = gates(node("Destinations", ["DestinationDesignations": .array([.string("FileNoDialog")]),
                                                 "FilenamePattern": .string("/${Name}"), "AllowOverwrite": .bool(false)]))
        #expect(listed == [RecipeGatedAction(.fileSystemAccess, target: "Writes files to a place decided when the recipe runs (/${Name})")])
        // A relative pattern stays in the output folder, whatever its values are: no permission, as before.
        #expect(gates(node("SaveFile", ["FilenamePattern": .string("${title}"), "AllowOverwrite": .bool(true)])).isEmpty)
        #expect(details(testRecipe([RecipeNode(id: "a", stepType: "Source"),
                                    RecipeNode(id: "b", stepType: "SaveFile", parameters: ["FilenamePattern": .string("${title}")])]))
            .contains("Saves the result to the output folder from the settings"))
    }

    /// RECIPES-2: a recipe without a destination step gets one when it runs (`RecipeTriggerPreparer`), which reads
    /// `OverrideDestinations`: a recipe that can set it needs the permissions of any destination, like a destination step.
    @Test func overrideDestinationsWithoutADestinationStep() {
        let set = node("SetVariable", ["Variable": .string("OverrideDestinations"), "Value": .array([.string("Dropbox")])])
        let recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), set], transitions: [("a", ["n"])])
        let validation = RecipeValidator().validate(recipe)
        #expect(validation.gateTypes == [.externalCommand, .networkAccess])
        let lines = details(recipe)
        #expect(lines.contains("Runs a command chosen when the recipe runs (the variable OverrideDestinations)"))
        #expect(lines.contains("Uploads to a destination chosen when the recipe runs (the variable OverrideDestinations)"))
        let actions = RecipeGates.actions(of: recipe, contracts: .builtIn, environment: .empty)
        #expect(Set(actions) == Set(validation.gatedActions))
        // A copy that adds the variable to a recipe approved without it doesn't run under that approval.
        let approved = testRecipe([RecipeNode(id: "a", stepType: "Source")], transitions: [])
        let changes = RecipeGates.unapprovedChanges(of: recipe, comparedWith: approved, contracts: .builtIn, environment: .empty)
        #expect(changes.count == 2)
        // A trigger argument that sets it counts too; a recipe that can't set it stays without permissions.
        var fromArgument = testRecipe([RecipeNode(id: "a", stepType: "Source")], transitions: [])
        #expect(RecipeValidator().validate(fromArgument).gateTypes.isEmpty)
        fromArgument.triggers = [TriggerConfig(triggerType: "Commandline", parameters: [
            "Command": .string("send"),
            "Arguments": .array([.object(["name": .string("to"), "variable": .string("OverrideDestinations")])])
        ])]
        #expect(RecipeValidator().validate(fromArgument).gateTypes == [.externalCommand, .networkAccess])
    }

    /// RECIPES-5: an annotation's picture file is read like the Source step's file; the microphone is asked for; and the
    /// step line shows the parameters that decide a permission, also after four others.
    @Test func annotationFilesAndTheMicrophoneNeedPermissions() {
        let picture = node("Annotation", ["Type": .string("Image"), "FilePath": .string("/x.png")])
        #expect(gates(picture) == [RecipeGatedAction(.fileSystemAccess, target: "Reads the image file /x.png")])
        let listed = node("Annotation", ["Annotations": .array([.object(["Type": .string("Text"), "Text": .string("Hi")]),
                                                                .object(["Type": .string("Icon"), "FilePath": .string("${Path}")])])])
        #expect(gates(listed) == [RecipeGatedAction(.fileSystemAccess, target: "Reads an image file named when the recipe runs (${Path})")])
        #expect(gates(node("Annotation", ["Type": .string("Text"), "Text": .string("Hi")])).isEmpty)

        let microphone = RecipeGatedAction(.custom, target: "Records the microphone")
        #expect(gates(node("RecordVideo", ["AudioSource": .string("Microphone")])) == [microphone])
        #expect(gates(node("RecordVideo", ["AudioSource": .string("systemAudioAndMicrophone")])) == [microphone])
        #expect(gates(node("RecordVideo", ["AudioSource": .string("${Audio}")]))
            == [RecipeGatedAction(.custom, target: "May record the microphone (the audio source is decided when the recipe runs (${Audio}))")])
        #expect(gates(node("RecordVideo", ["AudioSource": .string("SystemAudio")])).isEmpty)
        #expect(gates(node("RecordVideo", [:])).isEmpty)

        let video = node("RecordVideo", ["FrameRate": .number(30), "Bitrate": .number(2_000_000), "Format": .string("mp4"),
                                         "Preset": .string("Balanced"), "ColorMode": .string("Grayscale"), "AudioSource": .string("Microphone")])
        let lines = details(testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "RecordVideo", parameters: video.parameters)]))
        #expect(lines.contains { $0.hasPrefix("Record Video (") && $0.contains("AudioSource: Microphone") })
        #expect(lines.contains("Records the microphone"))
    }

    /// RECIPES-6: the step's own arguments replace those of a configured command, and the working folder is the step's:
    /// both are part of what the approval shows.
    @Test func literalArgumentsAndTheWorkingFolderAreShown() {
        let configured = GateEnvironment(commandLine: { $0 == "Optimize" ? "/usr/local/bin/pngquant" : nil })
        let own = gates(node("ExternalCommand", ["Command": .string("Optimize"), "Arguments": .string("--force --output /tmp/x {0}"),
                                                 "WorkingDirectory": .string("/tmp")]), configured)
        let target = "Optimize (/usr/local/bin/pngquant) with the arguments --force --output /tmp/x {0}, in the folder /tmp"
        #expect(own == [RecipeGatedAction(.externalCommand, target: target)])
        #expect(RecipeDescriber().describe(own[0]) == "Runs the program " + target)
        let folder = gates(node("ExternalCommand", ["CommandLine": .string("/bin/echo"), "WorkingDirectory": .string("${Dir}")]))
        #expect(folder.first?.target == "/bin/echo, in a folder decided when the recipe runs (${Dir})")
    }

    /// A variable name with spaces around it is the trimmed name when the step sets it, and `Variables` that is no literal
    /// object (a `${...}` that gives one) may set any variable: both count as setting `OverrideDestinations`.
    @Test func overrideDestinationsUnderAnotherSpellingOrFromAnObject() {
        let anyDestination: [RecipeGateType] = [.externalCommand, .networkAccess]
        func recipe(_ nodes: [RecipeNode]) -> CaptureRecipe {
            let all = [RecipeNode(id: "a", stepType: "Source")] + nodes
            return testRecipe(all, transitions: zip(all.dropLast(), all.dropFirst()).map { ($0.id, [$1.id]) })
        }
        let trailing = RecipeNode(id: "s", stepType: "SetVariable", parameters: ["Variable": .string("OverrideDestinations "),
                                                                                  "Value": .array([.string("Dropbox")])])
        #expect(RecipeValidator().validate(recipe([trailing])).gateTypes == anyDestination)
        let leading = RecipeNode(id: "s", stepType: "SetVariable", parameters: ["Variable": .string(" OverrideDestinations"),
                                                                                 "Value": .array([.string("Dropbox")])])
        let clipboard = RecipeNode(id: "d", stepType: "Destinations", parameters: ["DestinationDesignations": .array([.string("Clipboard")])])
        #expect(RecipeValidator().validate(recipe([leading, clipboard])).gateTypes == anyDestination)
        let object = RecipeNode(id: "s1", stepType: "SetVariable", parameters: ["Variable": .string("cfg"),
                                                                                 "Value": .object(["OverrideDestinations": .array([.string("Dropbox")])])])
        let fromObject = RecipeNode(id: "s2", stepType: "SetVariable", parameters: ["Variables": .string("${cfg}")])
        #expect(RecipeValidator().validate(recipe([object, fromObject])).gateTypes == anyDestination)
        // The other steps that set a variable named by a parameter.
        let barcode = RecipeNode(id: "q", stepType: "BarcodeScan", parameters: ["SetVariable": .string("OverrideDestinations\t")])
        #expect(RecipeValidator().validate(recipe([barcode])).gateTypes == anyDestination)
        let command = RecipeNode(id: "c", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/bin/echo"),
                                                                                    "SetOutputVariable": .string(" OverrideDestinations\n")])
        #expect(RecipeValidator().validate(recipe([command])).gateTypes == anyDestination)
        // A literal object of other names and a plain name stay as they were.
        let plain = RecipeNode(id: "s", stepType: "SetVariable", parameters: ["Variables": .object(["Title": .string("x")]),
                                                                               "Variable": .string(" Note ")])
        #expect(RecipeValidator().validate(recipe([plain])).gateTypes.isEmpty)
    }

    @Test func theLibraryAsksForTheseActions() async throws {
        let fixture = LibraryFixture(approver: StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: "x", approvedTriggers: request.triggers.map(\.key)))
        })
        defer { fixture.cleanUp() }
        let decided = RecipeNode(id: "send", stepType: "Destinations", parameters: ["DestinationDesignations": .string("${Dest}")])
        let url = try fixture.write(libraryRecipe(extraNode: decided))
        let result = await fixture.library.loadFile(url)
        #expect(fixture.library.recipes.isEmpty)
        #expect(result.errors.first?.contains("needs") == true)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.gates == [.externalCommand, .networkAccess])
    }
}

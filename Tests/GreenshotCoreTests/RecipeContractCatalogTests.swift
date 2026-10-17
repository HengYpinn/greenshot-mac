// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Testing
@testable import GreenshotCore

/// The step and trigger contracts (upstream's `[Step*]` attributes), gates, designations, requirements, hotkey text.
@Suite struct RecipeContractCatalogTests {
    static let wellKnown = [
        WellKnownStepType.source, WellKnownStepType.interactiveSelection, WellKnownStepType.immediateFeedback,
        WellKnownStepType.processors, WellKnownStepType.destinations, WellKnownStepType.notification,
        WellKnownStepType.dynamicDestination, WellKnownStepType.effect, WellKnownStepType.conditional,
        WellKnownStepType.textEffect, WellKnownStepType.annotation, WellKnownStepType.setVariable,
        WellKnownStepType.saveFile, WellKnownStepType.clipboard, WellKnownStepType.editor, WellKnownStepType.printer,
        WellKnownStepType.email, WellKnownStepType.customDestination, WellKnownStepType.userPrompt,
        WellKnownStepType.recordVideo, WellKnownStepType.stdout, WellKnownStepType.stderr, WellKnownStepType.slot,
        WellKnownStepType.externalCommand, WellKnownStepType.jira, WellKnownStepType.confluence, WellKnownStepType.box,
        WellKnownStepType.dropbox, WellKnownStepType.office, WellKnownStepType.pdf, WellKnownStepType.barcodeScan
    ]

    @Test func everyStepTypeHasAContract() {
        let catalog = StepContractCatalog.builtIn
        #expect(catalog.all.count == 31)
        for stepType in Self.wellKnown {
            #expect(catalog.contains(stepType), "\(stepType)")
        }
        #expect(catalog.contract(for: "effect")?.stepType == "Effect")
        #expect(catalog.contract(for: "Nonsense") == nil)
    }

    @Test func contractsMatchUpstreamAttributes() throws {
        let catalog = StepContractCatalog.builtIn
        let effect = try #require(catalog.contract(for: "Effect"))
        let effectType = try #require(effect.parameter("effect"))
        #expect(effectType.allowedValues.count == 12)
        #expect(effectType.defaultValue == .string("Border"))
        #expect(effect.payload.visualMutation == .mutatesPixels)
        let source = try #require(catalog.contract(for: "Source"))
        let sourceType = try #require(source.parameter("SourceType"))
        #expect(sourceType.supportsExpressions == false)
        #expect(source.payload.rawCapture == .created)
        let annotation = try #require(catalog.contract(for: "Annotation"))
        #expect(annotation.acceptsUndeclaredParameters)
        #expect(annotation.evaluatesOwnParameters)
        let saveFile = try #require(catalog.contract(for: "SaveFile"))
        #expect(saveFile.displayName == "Save to File")
        let filename = try #require(saveFile.outputVariables.first)
        #expect(filename.whenParameter == "SaveDirectory")
        let format = try #require(saveFile.parameter("Format"))
        #expect(format.effectiveAllowedValues.contains("png"))
    }

    @Test func variableNamesDependOnTheNode() throws {
        let catalog = StepContractCatalog.builtIn
        let setVariable = try #require(catalog.contract(for: "SetVariable"))
        var node = RecipeNode(id: "vars", stepType: "SetVariable",
                              parameters: ["variable": .string("One"), "variables": .object(["Two": .number(2), "Three": .string("x")])])
        let single = setVariable.outputVariables[0].resolveNames(for: node)
        #expect(single == ["One"])
        let keys = setVariable.outputVariables[1].resolveNames(for: node)
        #expect(keys == ["Two", "Three"])
        node.parameters["variable"] = nil
        #expect(setVariable.outputVariables[0].resolveNames(for: node).isEmpty)
        let prompt = try #require(catalog.contract(for: "UserPrompt"))
        let choice = prompt.outputVariables[0].resolveNames(for: RecipeNode(id: "ask", stepType: "UserPrompt"))
        #expect(choice == ["UserChoice.ask"])
    }

    @Test func conditionalOutputsGuaranteedByTheirParameter() throws {
        let destinations = try #require(StepContractCatalog.builtIn.contract(for: "Destinations"))
        let filename = try #require(destinations.outputVariables.first)
        let without = RecipeNode(id: "d", stepType: "Destinations")
        #expect(!filename.isGuaranteed(for: without))
        let with = RecipeNode(id: "d", stepType: "Destinations", parameters: ["saveDirectory": .string("~/Shots")])
        #expect(filename.isGuaranteed(for: with))
    }

    private func gates(_ node: RecipeNode, _ environment: GateEnvironment = .empty) -> [RecipeGatedAction] {
        StepContractCatalog.builtIn.contract(for: node.stepType)?.gates(node, environment) ?? []
    }

    @Test func gatesOfSources() {
        let region = RecipeNode(id: "s", stepType: "Source", parameters: ["sourceType": .string("Region")])
        #expect(gates(region).isEmpty)
        let file = RecipeNode(id: "s", stepType: "Source", parameters: ["sourceType": .string("file")])
        #expect(gates(file) == [RecipeGatedAction(.fileSystemAccess, target: "Reads the image file named in the variable Filename")])
    }

    @Test func gatesOfDestinations() {
        let environment = GateEnvironment(commandLine: { $0 == "Optimize" ? "/usr/local/bin/pngquant" : nil }, defaultDestinations: ["Box"])
        let save = RecipeNode(id: "d", stepType: "Destinations",
                              parameters: ["saveDirectory": .string("~/Shots"), "destinationDesignations": .array([.string("Jira"), .string("External Optimize")])])
        let actions = gates(save, environment)
        #expect(actions.count == 3)
        #expect(actions[0] == RecipeGatedAction(.fileSystemAccess, target: "Writes files to ~/Shots"))
        #expect(actions[1] == RecipeGatedAction(.networkAccess, target: "Jira"))
        #expect(actions[2] == RecipeGatedAction(.externalCommand, target: "/usr/local/bin/pngquant"))
        // Without designations: the destinations of the settings (upstream priority 4).
        let fromSettings = RecipeNode(id: "d", stepType: "Destinations")
        #expect(gates(fromSettings, environment) == [RecipeGatedAction(.networkAccess, target: "Box (box.com)")])
        let clipboard = RecipeNode(id: "c", stepType: "Clipboard")
        #expect(gates(clipboard, environment).isEmpty)
        let custom = RecipeNode(id: "c", stepType: "CustomDestination", parameters: ["customDestinationId": .string("Dropbox")])
        #expect(gates(custom).count == 1)
    }

    @Test func gatesOfPluginSteps() {
        let environment = GateEnvironment(commandLine: { $0 == "Paint" ? "/Applications/Paint.app" : nil })
        let named = RecipeNode(id: "e", stepType: "ExternalCommand", parameters: ["command": .string("Paint")])
        #expect(gates(named, environment) == [RecipeGatedAction(.externalCommand, target: "Paint (/Applications/Paint.app)")])
        let direct = RecipeNode(id: "e", stepType: "ExternalCommand", parameters: ["commandLine": .string("/bin/echo")])
        #expect(gates(direct) == [RecipeGatedAction(.externalCommand, target: "/bin/echo")])
        #expect(gates(RecipeNode(id: "j", stepType: "Jira")) == [RecipeGatedAction(.networkAccess, target: "Jira")])
        #expect(gates(RecipeNode(id: "p", stepType: "Pdf")).isEmpty)
        let video = RecipeNode(id: "v", stepType: "RecordVideo", parameters: ["outputDirectory": .string("~/Movies")])
        #expect(gates(video).count == 1)
    }

    @Test func gateEnvironmentFromSettings() {
        var settings = AppSettings()
        settings.destinations = [.clipboard, .dropbox]
        settings.externalCommands = [ExternalCommand(name: "Optimize", command: "/opt/bin/optimize", arguments: "{0}")]
        let environment = GateEnvironment(settings: settings)
        #expect(environment.defaultDestinations == ["Clipboard", "Dropbox"])
        #expect(environment.commandLine("optimize") == "/opt/bin/optimize")
    }

    @Test func designations() {
        #expect(RecipeDestinationDesignation("FileNoDialog").destination == .file)
        #expect(RecipeDestinationDesignation("file").destination == .file)
        #expect(RecipeDestinationDesignation("EMail").destination == .email)
        #expect(RecipeDestinationDesignation("OneNote").destination == .notes)
        #expect(RecipeDestinationDesignation("openWith").destination == .openWith)
        #expect(RecipeDestinationDesignation("Martian").destination == nil)
        let external = RecipeDestinationDesignation("External MS Paint")
        #expect(external.destination == .externalCommand)
        #expect(external.externalCommandName == "MS Paint")
        for destination in CaptureDestination.allCases where destination != .externalCommand {
            let name = RecipeDestinationDesignation.designation(for: destination)
            #expect(RecipeDestinationDesignation(name).destination == destination, "\(destination)")
        }
        #expect(RecipeDestinationDesignation("Editor").displayName == "Open in image editor (Editor)")
    }

    @Test func triggerContracts() throws {
        let catalog = TriggerContractCatalog.builtIn
        #expect(catalog.all.count == 11)
        let clipboard = try #require(catalog.contract(for: "clipboard"))
        #expect(clipboard.startsOnItsOwn)
        #expect(clipboard.defaultSourceType == "Clipboard")
        let hotkey = try #require(catalog.contract(for: "Hotkey"))
        #expect(!hotkey.startsOnItsOwn)
        let openFile = try #require(catalog.contract(for: "OpenFile"))
        #expect(openFile.providedVariables.first?.name == "Filename")
        #expect(BuiltInTriggerContracts.isValidToolName("capture_region-2"))
        #expect(!BuiltInTriggerContracts.isValidToolName("bad name"))
        #expect(!BuiltInTriggerContracts.isValidToolName(String(repeating: "a", count: 65)))
    }

    @Test func requirements() {
        let catalog = RecipeRequirementCatalog.builtIn
        #expect(catalog.problem(with: RecipeRequirement(id: "Greenshot.Plugin.Zxing", minVersion: "9.0")) == nil)
        #expect(catalog.problem(with: RecipeRequirement(id: "zxing")) == nil)
        let missing = catalog.problem(with: RecipeRequirement(id: "Acme.Plugin", name: "Acme", minVersion: "1.2", url: "https://acme.example"))
        #expect(missing == "This recipe requires the extension 'Acme' (v1.2+) (ID: Acme.Plugin), which is not installed or is disabled. Download/install from: https://acme.example")
        #expect(catalog.problem(with: RecipeRequirement(id: " ")) == "Recipe requirement is missing required 'id'.")
    }

    @Test func hotkeyTextParses() throws {
        let combo = try #require(RecipeHotkeyText.parse("Ctrl + Shift + B"))
        #expect(combo.keyCode == UInt32(kVK_ANSI_B))
        let expected = KeyCombo.command | KeyCombo.shift
        #expect(combo.modifiers == expected)
        let win = try #require(RecipeHotkeyText.parse("Win + Alt + F5"))
        let winExpected = KeyCombo.control | KeyCombo.option
        #expect(win.modifiers == winExpected)
        let sequence = try #require(RecipeHotkeyText.parse("Ctrl + K, C"))
        #expect(sequence.followingChords.count == 1)
        let print = try #require(RecipeHotkeyText.parse("PrintScreen"))
        #expect(print.keyCode == UInt32(kVK_F13))
        let mac = try #require(RecipeHotkeyText.parse("⌘ + ⌥ + 4"))
        let macExpected = KeyCombo.command | KeyCombo.option
        #expect(mac.modifiers == macExpected)
        let left = try #require(RecipeHotkeyText.parse("Ctrl (L) + Alt + K"))
        #expect(left.sides.command == .left)
    }

    @Test func hotkeyTextProblems() {
        #expect(RecipeHotkeyText.problem(with: "Ctrl + Shift + B") == nil)
        #expect(RecipeHotkeyText.problem(with: "") == "No hotkey set.")
        #expect(RecipeHotkeyText.problem(with: "Ctrl + Banana") == "'Banana' is not a key Greenshot knows.")
        #expect(RecipeHotkeyText.problem(with: "Ctrl + Shift") == "'Ctrl + Shift' has no key, only modifiers.")
        #expect(RecipeHotkeyText.problem(with: "B") == "Keys other than F1–F20 need ⌃, ⌥ or ⌘.")
        #expect(RecipeHotkeyText.problem(with: "F7") == nil)
    }

    @Test func hotkeyTextRoundTrips() throws {
        for text in ["Ctrl + Shift + B", "Ctrl + Alt + Win + 4", "PrintScreen", "Ctrl + K, C", "Shift + F12", "Alt (R) + Delete"] {
            let combo = try #require(RecipeHotkeyText.parse(text), "\(text)")
            #expect(RecipeHotkeyText.format(combo) == text, "\(text)")
        }
    }
}

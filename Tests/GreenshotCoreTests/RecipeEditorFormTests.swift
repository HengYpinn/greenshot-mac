// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeEditorFormTests {
    private func field(_ stepType: String, _ name: String) throws -> RecipeEditorField {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: stepType))
        return try #require(RecipeEditorForm.fields(for: contract).first { $0.name == name })
    }

    @Test func everyContractGivesAForm() {
        for contract in StepContractCatalog.builtIn.all {
            let fields = RecipeEditorForm.fields(for: contract)
            #expect(fields.count == contract.parameters.count, "\(contract.stepType)")
            for field in fields where field.kind == .json {
                // Only objects without an editor of their own fall back to JSON text.
                #expect(contract.parameter(field.name)?.dataType == .object, "\(contract.stepType).\(field.name)")
            }
        }
        for contract in TriggerContractCatalog.builtIn.all {
            #expect(RecipeEditorForm.fields(for: contract).count == contract.parameters.count, "\(contract.triggerType)")
        }
    }

    @Test func structuredEditors() throws {
        #expect(try field("Conditional", "Branches").kind == .branchTable)
        #expect(try field("UserPrompt", "Choices").kind == .choiceTable)
        #expect(try field("SetVariable", "Variables").kind == .keyValueTable)
        #expect(try field("TextEffect", "Patterns").kind == .stringList)
        #expect(try field("Destinations", "DestinationDesignations").kind == .destinationList)
        #expect(try field("DynamicDestination", "Destinations").kind == .destinationList)
        #expect(try field("Effect", "Edges").kind == .edges)
        #expect(try field("Slot", "Accept").kind == .accept)
        #expect(try field("Annotation", "Annotations").kind == .annotations)
        #expect(try field("ImmediateFeedback", "SoundFilePath").kind == .soundFile)
        #expect(try field("Effect", "Color").kind == .color)
        #expect(try field("Source", "WindowHandle").kind == .text)
        let hotkey = try #require(TriggerContractCatalog.builtIn.contract(for: "Hotkey"))
        #expect(RecipeEditorForm.fields(for: hotkey).first?.kind == .hotkey)
        let commandline = try #require(TriggerContractCatalog.builtIn.contract(for: "Commandline"))
        #expect(RecipeEditorForm.fields(for: commandline).first { $0.name == "Arguments" }?.kind == .arguments)
    }

    @Test func enumChoicesComeFromTheContract() throws {
        #expect(try field("Source", "SourceType").kind == .choice(["Region", "Window", "ActiveWindow", "FullScreen", "LastRegion",
                                                                    "Clipboard", "File", "TextOcr", "CurrentEditor", "Extension"]))
        // The file formats come from a provider.
        guard case .choice(let formats) = try field("SaveFile", "Format").kind else {
            Issue.record("Format is not a choice")
            return
        }
        #expect(formats.contains("png"))
        #expect(try field("Source", "SourceType").supportsExpressions == false)
    }

    @Test func effectParametersBelongToTheirEffects() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        let effects = try #require(contract.parameter("Effect")).allowedValues
        for field in RecipeEditorForm.fields(for: contract) where field.name != "Effect" {
            let condition = try #require(field.condition, "\(field.name) has no effect")
            #expect(condition.parameter == "Effect")
            for value in condition.values { #expect(effects.contains(value), "\(field.name): \(value)") }
        }
        #expect(try field("Effect", "Darkness").condition?.values == ["DropShadow", "TornEdge"])
    }

    @Test func sourceTypeConditions() throws {
        #expect(try field("Source", "Filename").condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["File"]))
        #expect(try field("Source", "WindowTitle").condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["Window"]))
        #expect(try field("Source", "DelayMs").condition == nil)
        #expect(try field("RecordVideo", "MonitorIndex").condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["Monitor"]))
    }

    @Test func visibilityFollowsTheSelector() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        var node = RecipeNode(id: "e", stepType: "Effect", parameters: ["Effect": .string("Border")])
        let width = try field("Effect", "Width")
        let darkness = try field("Effect", "Darkness")
        #expect(RecipeEditorForm.isVisible(width, in: node, contract: contract))
        #expect(!RecipeEditorForm.isVisible(darkness, in: node, contract: contract))
        node.parameters["Effect"] = .string("${option.effect}")
        #expect(RecipeEditorForm.isVisible(darkness, in: node, contract: contract))
        // Without a value the default (Border) counts.
        node.parameters["Effect"] = nil
        #expect(RecipeEditorForm.isVisible(width, in: node, contract: contract))
    }

    @Test func destinationParametersByDesignation() throws {
        let destinations = try #require(StepContractCatalog.builtIn.contract(for: "Destinations"))
        let printer = try #require(StepContractCatalog.builtIn.contract(for: "Printer"))
        let saveFile = try #require(StepContractCatalog.builtIn.contract(for: "SaveFile"))
        func visible(_ contract: StepContract, _ node: RecipeNode) -> [String] {
            RecipeEditorForm.fields(for: contract).filter { RecipeEditorForm.isVisible($0, in: node, contract: contract) }.map(\.name)
        }
        let printerFields = visible(printer, RecipeNode(id: "p", stepType: "Printer"))
        #expect(printerFields.contains("ShowPrintDialog"))
        #expect(!printerFields.contains("SaveDirectory"))
        #expect(!printerFields.contains("ClipboardMode"))
        let fileFields = visible(saveFile, RecipeNode(id: "f", stepType: "SaveFile"))
        #expect(fileFields.contains("SaveDirectory"))
        #expect(!fileFields.contains("DestinationDesignations"))
        #expect(!fileFields.contains("TargetEditor"))
        let multi = visible(destinations, RecipeNode(id: "d", stepType: "Destinations",
                                                     parameters: ["DestinationDesignations": .array([.string("Clipboard")])]))
        #expect(multi.contains("ClipboardMode"))
        #expect(!multi.contains("PrinterName"))
        #expect(!multi.contains("CustomDestinationId"))
        #expect(multi.contains("DestinationDesignations"))
    }

    @Test func labels() {
        #expect(RecipeEditorForm.label(for: "DelayMs") == "Delay (ms)")
        #expect(RecipeEditorForm.label(for: "ShadowOffsetX") == "Shadow Offset X")
        #expect(RecipeEditorForm.label(for: "ClipboardFormatHTMLDataUrl") == "Clipboard Format HTML Data URL")
        #expect(RecipeEditorForm.label(for: "CustomDestinationId") == "Custom Destination ID")
        #expect(RecipeEditorForm.label(for: "PageWidthMm") == "Page Width Mm")
    }

    @Test func valuesKeepExpressionsAndClear() {
        var parameters: JSONObject = ["delayMs": .number(100)]
        RecipeEditorForm.set(.number(200), for: "DelayMs", in: &parameters)
        #expect(parameters.keys == ["delayMs"])
        #expect(parameters["DelayMs"] == .number(200))
        RecipeEditorForm.set(nil, for: "DelayMs", in: &parameters)
        #expect(parameters.isEmpty)
        #expect(RecipeEditorForm.numberValue("42", decimal: false) == .number(42))
        #expect(RecipeEditorForm.numberValue("0.5", decimal: true) == .number(0.5))
        #expect(RecipeEditorForm.numberValue("${payload.width / 2}", decimal: false) == .string("${payload.width / 2}"))
        #expect(RecipeEditorForm.numberValue("  ", decimal: false) == nil)
        #expect(RecipeEditorForm.isExpression(.string("${option.x}")))
        #expect(!RecipeEditorForm.isExpression(.number(1)))
    }

    @Test func undeclaredParametersAreKept() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        let node = RecipeNode(id: "e", stepType: "Effect", parameters: ["Effect": .string("Border"), "Sparkle": .bool(true)])
        #expect(RecipeEditorForm.undeclaredKeys(of: node, contract: contract) == ["Sparkle"])
    }

    @Test func annotationSchemaCoversTheFactoryKeys() {
        let qr = RecipeAnnotationSchema.fields(forType: "QRCode").map(\.name)
        #expect(qr.contains("QrType"))
        #expect(RecipeAnnotationSchema.qrFields(forType: "WiFi").map(\.name) == ["WifiSsid", "WifiPassword", "WifiEncryption"])
        #expect(RecipeAnnotationSchema.fields(forType: "Text").map(\.name).contains("FontFamily"))
        #expect(RecipeAnnotationSchema.fields(forType: "Freehand").map(\.name).contains("Points"))
        for type in RecipeAnnotationSchema.types {
            #expect(!RecipeAnnotationSchema.fields(forType: type).isEmpty, "\(type)")
        }
        #expect(RecipeAnnotationSchema.summary(["Type": .string("Text"), "Text": .string("Hello")]) == "Text: Hello")
    }
}

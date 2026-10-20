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
        return try #require(RecipeParameterForm.fields(for: contract).first { $0.name == name })
    }

    @Test func everyContractGivesAForm() {
        for contract in StepContractCatalog.builtIn.all {
            let fields = RecipeParameterForm.fields(for: contract)
            #expect(fields.count == contract.parameters.count, "\(contract.stepType)")
            for field in fields where field.kind == .json {
                // Only objects without an editor of their own fall back to JSON text.
                #expect(contract.parameter(field.name)?.dataType == .object, "\(contract.stepType).\(field.name)")
            }
        }
        for contract in TriggerContractCatalog.builtIn.all {
            #expect(RecipeParameterForm.fields(for: contract).count == contract.parameters.count, "\(contract.triggerType)")
        }
    }

    @Test func structuredEditors() throws {
        let made1 = try field("Conditional", "Branches")
        #expect(made1.kind == .branchTable)
        let made2 = try field("UserPrompt", "Choices")
        #expect(made2.kind == .choiceTable)
        let made3 = try field("SetVariable", "Variables")
        #expect(made3.kind == .keyValueTable)
        let made4 = try field("TextEffect", "Patterns")
        #expect(made4.kind == .stringList)
        let made5 = try field("Destinations", "DestinationDesignations")
        #expect(made5.kind == .destinationList)
        let made6 = try field("DynamicDestination", "Destinations")
        #expect(made6.kind == .destinationList)
        let made7 = try field("Effect", "Edges")
        #expect(made7.kind == .edges)
        let made8 = try field("Slot", "Accept")
        #expect(made8.kind == .accept)
        let made9 = try field("Annotation", "Annotations")
        #expect(made9.kind == .annotations)
        let made10 = try field("ImmediateFeedback", "SoundFilePath")
        #expect(made10.kind == .soundFile)
        let made11 = try field("Effect", "Color")
        #expect(made11.kind == .color)
        let made12 = try field("Source", "WindowHandle")
        #expect(made12.kind == .text)
        let hotkey = try #require(TriggerContractCatalog.builtIn.contract(for: "Hotkey"))
        #expect(RecipeParameterForm.fields(for: hotkey).first?.kind == .hotkey)
        let commandline = try #require(TriggerContractCatalog.builtIn.contract(for: "Commandline"))
        #expect(RecipeParameterForm.fields(for: commandline).first { $0.name == "Arguments" }?.kind == .arguments)
    }

    @Test func enumChoicesComeFromTheContract() throws {
        let made13 = try field("Source", "SourceType")
        #expect(made13.kind == .choice(["Region", "Window", "ActiveWindow", "FullScreen", "LastRegion",
                                                                    "Clipboard", "File", "TextOcr", "CurrentEditor", "Extension"]))
        // The file formats come from a provider.
        guard case .choice(let formats) = try field("SaveFile", "Format").kind else {
            Issue.record("Format is not a choice")
            return
        }
        #expect(formats.contains("png"))
        let made14 = try field("Source", "SourceType")
        #expect(made14.supportsExpressions == false)
    }

    @Test func effectParametersBelongToTheirEffects() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        let effects = try #require(contract.parameter("Effect")).allowedValues
        for field in RecipeParameterForm.fields(for: contract) where field.name != "Effect" {
            let condition = try #require(field.condition, "\(field.name) has no effect")
            #expect(condition.parameter == "Effect")
            for value in condition.values { #expect(effects.contains(value), "\(field.name): \(value)") }
        }
        let made15 = try field("Effect", "Darkness")
        #expect(made15.condition?.values == ["DropShadow", "TornEdge"])
    }

    @Test func sourceTypeConditions() throws {
        let made16 = try field("Source", "Filename")
        #expect(made16.condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["File"]))
        let made17 = try field("Source", "WindowTitle")
        #expect(made17.condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["Window"]))
        let made18 = try field("Source", "DelayMs")
        #expect(made18.condition == nil)
        let made19 = try field("RecordVideo", "MonitorIndex")
        #expect(made19.condition == RecipeEditorFieldCondition(parameter: "SourceType", values: ["Monitor"]))
    }

    @Test func visibilityFollowsTheSelector() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        var node = RecipeNode(id: "e", stepType: "Effect", parameters: ["Effect": .string("Border")])
        let width = try field("Effect", "Width")
        let darkness = try field("Effect", "Darkness")
        #expect(RecipeParameterForm.isVisible(width, in: node, contract: contract))
        #expect(!RecipeParameterForm.isVisible(darkness, in: node, contract: contract))
        node.parameters["Effect"] = .string("${option.effect}")
        #expect(RecipeParameterForm.isVisible(darkness, in: node, contract: contract))
        // Without a value the default (Border) counts.
        node.parameters["Effect"] = nil
        #expect(RecipeParameterForm.isVisible(width, in: node, contract: contract))
    }

    @Test func destinationParametersByDesignation() throws {
        let destinations = try #require(StepContractCatalog.builtIn.contract(for: "Destinations"))
        let printer = try #require(StepContractCatalog.builtIn.contract(for: "Printer"))
        let saveFile = try #require(StepContractCatalog.builtIn.contract(for: "SaveFile"))
        func visible(_ contract: StepContract, _ node: RecipeNode) -> [String] {
            RecipeParameterForm.fields(for: contract).filter { RecipeParameterForm.isVisible($0, in: node, contract: contract) }.map(\.name)
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
        #expect(RecipeParameterForm.label(for: "DelayMs") == "Delay (ms)")
        #expect(RecipeParameterForm.label(for: "ShadowOffsetX") == "Shadow Offset X")
        #expect(RecipeParameterForm.label(for: "ClipboardFormatHTMLDataUrl") == "Clipboard Format HTML Data URL")
        #expect(RecipeParameterForm.label(for: "CustomDestinationId") == "Custom Destination ID")
        #expect(RecipeParameterForm.label(for: "PageWidthMm") == "Page Width Mm")
    }

    @Test func valuesKeepExpressionsAndClear() {
        var parameters: JSONObject = ["delayMs": .number(100)]
        RecipeParameterForm.set(.number(200), for: "DelayMs", in: &parameters)
        #expect(parameters.keys == ["delayMs"])
        #expect(parameters["DelayMs"] == .number(200))
        RecipeParameterForm.set(nil, for: "DelayMs", in: &parameters)
        #expect(parameters.isEmpty)
        #expect(RecipeParameterForm.numberValue("42", decimal: false) == .number(42))
        #expect(RecipeParameterForm.numberValue("0.5", decimal: true) == .number(0.5))
        #expect(RecipeParameterForm.numberValue("${payload.width / 2}", decimal: false) == .string("${payload.width / 2}"))
        #expect(RecipeParameterForm.numberValue("  ", decimal: false) == nil)
        #expect(RecipeParameterForm.isExpression(.string("${option.x}")))
        #expect(!RecipeParameterForm.isExpression(.number(1)))
    }

    /// A text `Patterns` is one regular expression to TextEffect, a text `ProcessorIds` is split at `,` and `;` by
    /// Processors: the field shows each as its step reads it (it split both, and editing stored the pieces).
    @Test func stringListsShowTextAsTheStepReadsIt() {
        let pattern = JSONValue.string("\\d{1,3}\\.\\d{1,3}")
        #expect(RecipeParameterForm.listLines(pattern, field: "Patterns") == ["\\d{1,3}\\.\\d{1,3}"])
        #expect(RecipeParameterForm.listLines(pattern, field: "patterns") == TextEffectExecutor.patterns(pattern))
        let ids = JSONValue.string("ocr; other")
        #expect(RecipeParameterForm.listLines(ids, field: "ProcessorIds") == ["ocr", "other"])
        #expect(RecipeParameterForm.listLines(.array([.string("a,b"), .string("c")]), field: "Patterns") == ["a,b", "c"])
        #expect(RecipeParameterForm.listLines(nil, field: "Patterns").isEmpty)
    }

    /// One item per line, blank lines left out; an emptied list removes the parameter (it stored [""], so a missing
    /// `Patterns` wasn't reported and the step found nothing).
    @Test func stringListsStoreTheirLines() {
        #expect(RecipeParameterForm.listValue("") == nil)
        #expect(RecipeParameterForm.listValue("\n  \n") == nil)
        #expect(RecipeParameterForm.listValue("a\n\n b\n") == .array([.string("a"), .string(" b")]))
        #expect(RecipeParameterForm.listValue("a\r\nb") == .array([.string("a"), .string("b")]))
    }

    @Test func undeclaredParametersAreKept() throws {
        let contract = try #require(StepContractCatalog.builtIn.contract(for: "Effect"))
        let node = RecipeNode(id: "e", stepType: "Effect", parameters: ["Effect": .string("Border"), "Sparkle": .bool(true)])
        #expect(RecipeParameterForm.undeclaredKeys(of: node, contract: contract) == ["Sparkle"])
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

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The app's side of the destination steps (upstream `DestinationExportStep` with `DestinationDispatcher`; the order,
/// the picker loop and the automatic steps per destination are Core's `RecipeDestinationDispatcher`): a designation as
/// the app's `DestinationTarget`, an export through `OutputManager` like a capture's, with the step's options for the
/// file (SaveDirectory, FilenamePattern, Format, quality…), the editor (TargetEditor) and the printer.
struct RecipeAppExporter: RecipeExporting {
    let runtime: RecipeRuntime

    func prepare(_ step: RecipeStepInvocation, payload: RecipePayload, in context: RecipeFlowContext) async {
        let values = await MainActor.run { Self.fileVariables(step, payload: payload, runtime: runtime) }
        for (name, value) in values { context[variable: name] = value }
    }

    func target(for designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async -> RecipeExportTarget? {
        await MainActor.run { Self.target(for: designation, step: step, settings: runtime.app.settings.value) }
    }

    func pick(_ payload: RecipePayload, in context: RecipeFlowContext) async -> RecipeExportTarget? {
        await Self.pick(payload, runtime: runtime)
    }

    func export(_ payload: RecipePayload, to target: RecipeExportTarget, step: RecipeStepInvocation,
                in context: RecipeFlowContext) async -> ExportResult {
        await Self.export(payload, to: target, step: step, context: context, runtime: runtime)
    }

    // MARK: Targets

    /// A designation as the app's destination; nil when there is none or an administrator turned it off (upstream
    /// `IsAvailableFor`).
    @MainActor
    static func target(for designation: String, step: RecipeStepInvocation?, settings: AppSettings) -> RecipeExportTarget? {
        guard let destination = RecipeDestinationPlan.destination(of: designation).destination else { return nil }
        if settings.isDestinationExcluded(destination) {
            log.info("The destination '\(designation)' is turned off by an administrator; the recipe skips it.")
            return nil
        }
        switch destination {
        case .externalCommand:
            // The automatic steps of one command are stored for "External <command name>" (RMANAGER, upstream).
            let named = RecipeDestinationPlan.externalCommandDesignation(designation, commands: settings.externalCommands.map(\.name))
            let name = RecipeDestinationPlan.destination(of: named).commandName ?? ""
            guard !name.isEmpty else { return RecipeExportTarget(designation: named, detail: DestinationTarget.destination(.externalCommand)) }
            guard let command = settings.externalCommands.first(where: { recipeEquals($0.name, name) }) else {
                log.warn("There is no external command '\(name)' in the settings.")
                return nil
            }
            return RecipeExportTarget(designation: "External \(command.name)", detail: DestinationTarget.externalCommand(command))
        case .printer:
            if let name = step?.string("PrinterName")?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                return RecipeExportTarget(designation: designation, detail: DestinationTarget.printer(name))
            }
            return RecipeExportTarget(designation: designation, detail: DestinationTarget.destination(.printer))
        default:
            return RecipeExportTarget(designation: designation, detail: DestinationTarget.destination(destination))
        }
    }

    /// The designation of what the picker offers (for the automatic steps that run per destination).
    static func designation(of target: DestinationTarget) -> String {
        switch target {
        case .destination(let destination): return RecipeDestinationDesignation.designation(for: destination)
        case .pdfAs: return "Pdf"
        case .externalCommand(let command): return "External \(command.name)"
        case .application: return "OpenWith"
        case .addToEditor: return "Editor"
        case .printer: return "Printer"
        case .jiraIssue: return "Jira"
        case .confluencePage: return "Confluence"
        case .office(let app, _): return app == .mail ? "EMail" : RecipeDestinationDesignation.designation(for: app.destination)
        }
    }

    /// The destination picker (upstream `PickerDestination`): the choice is returned, the dispatcher exports.
    @MainActor
    static func pick(_ payload: RecipePayload, runtime: RecipeRuntime) async -> RecipeExportTarget? {
        let output = runtime.app.output
        let capture = payload.exportCapture()
        let menu = NSMenu(title: "Send screenshot to")
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "\(capture.image.width) × \(capture.image.height) – \(capture.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        var picked: DestinationTarget?
        output.pickerItems(for: capture) { picked = $0 }.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Discard") {})
        output.popUp(menu)
        guard let picked else { return nil }
        return RecipeExportTarget(designation: designation(of: picked), detail: picked)
    }

    // MARK: Exports

    @MainActor
    static func export(_ payload: RecipePayload, to target: RecipeExportTarget, step: RecipeStepInvocation,
                       context: RecipeFlowContext, runtime: RecipeRuntime) async -> ExportResult {
        let app = runtime.app
        let capture = payload.exportCapture()
        let state = runtime.flowState(context.executionId)
        state.holdMessages(of: capture, settings: app.settings)
        guard let destinationTarget = target.detail as? DestinationTarget else { return .declined }
        var result: ExportResult
        switch destinationTarget {
        case .destination(.editor), .addToEditor:
            result = openInEditor(payload, step: step, context: context, runtime: runtime)
        case .destination(.file) where !RecipeFileExportOptions(step).isEmpty:
            result = saveFile(capture, options: RecipeFileExportOptions(step), context: context, runtime: runtime)
        case .destination(.printer), .printer:
            result = await withPrintOptions(step, runtime: runtime) {
                await perform(destinationTarget, capture: capture, output: app.output)
            }
        default:
            result = await perform(destinationTarget, capture: capture, output: app.output)
        }
        if result.exportedBy == nil { result.exportedBy = destinationTarget.displayName }
        state.record(result)
        return result
    }

    /// `OutputManager.perform` as an async call: its completion comes once.
    @MainActor
    static func perform(_ target: DestinationTarget, capture: Capture, output: OutputManager) async -> ExportResult {
        await withCheckedContinuation { continuation in
            var resumed = false
            output.perform(target, with: capture) { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
        }
    }

    /// The Editor destination (upstream `EditorDestination` with `TargetEditor`): the capture with its elements still
    /// editable; NewEditor a new window, AvailableEditor an editor without unsaved changes, CurrentEditor the editor
    /// of the Editor trigger, unset as Settings › Editor says. Not for an AI tool's flow.
    @MainActor
    static func openInEditor(_ payload: RecipePayload, step: RecipeStepInvocation, context: RecipeFlowContext,
                             runtime: RecipeRuntime) -> ExportResult {
        if recipeEquals(context.trigger?.triggerType ?? "", WellKnownTriggerType.aiTool) {
            context.log("An AI tool's capture doesn't open the editor.")
            return .declined
        }
        let editors = runtime.app.editors
        let wanted = step.string("TargetEditor")?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let reuse = wanted.isEmpty ? runtime.app.settings.value.reuseEditor : wanted == "availableeditor"
        var editor: EditorWindowController?
        if wanted == "currenteditor" {
            editor = (context.object(forKey: "EditorForm") as? RecipeEditorForm)?.editor
            if editor == nil { log.warn("There is no editor of the Editor trigger; another editor is used.") }
        }
        if editor == nil, reuse || wanted == "currenteditor" { editor = editors.reusableEditor() }
        if let editor {
            editor.show(payload.image, scale: payload.scale, title: payload.title, date: payload.captureDate)
            editor.editorDocument.addOpened(payload.annotations)
            editor.canvas.documentChanged()
            editor.window?.makeKeyAndOrderFront(nil)
            editor.window?.orderFrontRegardless()
            NSApp.activate()
        } else {
            editors.open(payload.editorDocument())
        }
        var result = ExportResult.succeeded(clearsModified: false)
        result.exportedBy = "Editor"
        return result
    }

    // MARK: File

    /// `Destination.*` before the exports (upstream `ApplyCustomFileSettings`): the options, and with `SaveDirectory`
    /// the folder and the file of this capture (the file name counts `${NUM}` here, once).
    @MainActor
    static func fileVariables(_ step: RecipeStepInvocation, payload: RecipePayload, runtime: RecipeRuntime) -> [String: JSONValue] {
        let options = RecipeFileExportOptions(step)
        guard !options.isEmpty else { return [:] }
        let settings = runtime.app.settings
        let s = settings.value
        var values = options.variables(defaultFormat: s.outputFormat, defaultQuality: s.jpegQuality, defaultReduceColors: s.reduceColors)
        if let directory = options.saveDirectory {
            _ = payload.exportCapture()
            let folder = DestinationSupport.outputFolder(directory, context: settings.patternContext(title: payload.title,
                                                                                                    date: payload.captureDate,
                                                                                                    consumeNumber: false))
            let name = FilenamePattern.fileName(options.filenamePattern ?? s.filenamePattern,
                                                context: settings.patternContext(title: payload.title, date: payload.captureDate))
            let format = options.format ?? s.outputFormat
            let file = folder.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
            values["Destination.SaveDirectory"] = .string(folder.path)
            values["Destination.Filename"] = .string(file.path)
        }
        return values
    }

    /// "Save directly" with the step's options (upstream `FileDestination` with `FileDestinationOptions`).
    @MainActor
    static func saveFile(_ capture: Capture, options: RecipeFileExportOptions, context: RecipeFlowContext,
                         runtime: RecipeRuntime) -> ExportResult {
        let settings = runtime.app.settings
        let saver = runtime.app.saver
        let s = settings.value
        let format = options.format ?? s.outputFormat
        var url: URL
        if let planned = context[variable: "Destination.Filename"]?.asString, !planned.isEmpty {
            url = URL(fileURLWithPath: planned)
        } else {
            let folder = saver.outputFolderURL(title: capture.title, date: capture.date)
            let name = FilenamePattern.fileName(options.filenamePattern ?? s.filenamePattern,
                                                context: settings.patternContext(title: capture.title, date: capture.date))
            let base = name.hasPrefix("/") ? URL(fileURLWithPath: name) : folder.appendingPathComponent(name)
            url = base.appendingPathExtension(format.fileExtension)
        }
        if !(options.allowOverwrite ?? s.allowOverwrite) { url = DestinationSupport.uniqueURL(for: url) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if format == .greenshot {
                let contents = capture.editable ?? GreenshotFile.Contents(image: capture.image, scale: capture.scale, title: capture.title,
                                                                          captureDate: capture.date)
                try contents.write(to: url)
            } else {
                var output = ImageOutputOptions(settings: s, format: format, scale: capture.scale, title: capture.title)
                if let quality = options.jpegQuality { output.jpegQuality = quality }
                if let reduce = options.reduceColors { output.reduceColors = reduce }
                if options.promptQuality ?? s.promptJpegQuality, DestinationSupport.asksQuality(format) {
                    guard let choice = QualityForm.ask(format: format, settings: settings) else { return .declined }
                    output.jpegQuality = choice.quality
                    output.reduceColors = choice.reduceColors
                }
                try ImageExporter.write(capture.image, to: url, options: output)
            }
        } catch {
            log.error("A recipe could not save \(url.lastPathComponent)", error: error)
            return .failed(error.localizedDescription, target: url.lastPathComponent)
        }
        saver.notifySaved(url, copyPath: false)
        if options.copyPathToClipboard ?? s.copyPathToClipboard { Clipboard.copy(text: url.path) }
        var result = ExportResult.succeeded(fileURL: url)
        result.exportedBy = "Save"
        return result
    }

    // MARK: Printer

    /// The step's print options for this one print (upstream `PrintOptions` of `DestinationExportStep`): the printing
    /// code reads `Printing.settings`, so it gets a copy of the settings with the options for the call.
    @MainActor
    static func withPrintOptions(_ step: RecipeStepInvocation, runtime: RecipeRuntime,
                                 _ body: () async -> ExportResult) async -> ExportResult {
        let base = runtime.app.settings.value
        guard let printing = printOptions(step, base: base.printing) else { return await body() }
        var copy = base
        copy.printing = printing
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-recipe-print-\(UUID().uuidString).json")
        do {
            try SettingsStorage.save(copy, toFile: file)
        } catch {
            log.warn("The print options of the recipe could not be used.", error: error)
            return await body()
        }
        let previous = Printing.settings
        Printing.settings = SettingsStore(fileURL: file)
        defer {
            Printing.settings = previous
            try? FileManager.default.removeItem(at: file)
        }
        return await body()
    }

    /// The print settings with the step's options; nil when the step sets none.
    static func printOptions(_ step: RecipeStepInvocation, base: PrintSettings) -> PrintSettings? {
        var options = base
        var changed = false
        func flag(_ name: String, _ keyPath: WritableKeyPath<PrintSettings, Bool>) {
            guard step.isSet(name), let value = step.bool(name) else { return }
            options[keyPath: keyPath] = value
            changed = true
        }
        flag("ShowPrintDialog", \.promptOptions)
        flag("AllowRotate", \.allowRotate)
        flag("AllowEnlarge", \.allowEnlarge)
        flag("AllowShrink", \.allowShrink)
        flag("Center", \.center)
        flag("PrintFooter", \.footer)
        if step.isSet("FooterPattern"), let pattern = step.string("FooterPattern") {
            options.footerPattern = pattern
            changed = true
        }
        if step.isSet("ColorMode"), let mode = step.string("ColorMode")?.lowercased() {
            options.grayscale = mode == "grayscale"
            options.monochrome = mode == "monochrome"
            changed = true
        }
        return changed ? options : nil
    }
}

// MARK: Clipboard step

/// Upstream's Clipboard step (`ExecuteClipboardExportAsync`): the image and/or the text (the extracted text, else OCR;
/// `ClipboardCustomText` with `${ocr_text}`), in the step's formats; the BeforeDestination automatic steps of
/// "Clipboard" change a copy first.
struct RecipeClipboardStepExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime
    let steps: RecipeStepRegistry

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        context.state = .exporting
        guard var payload = context.payload else {
            context.log("Clipboard skipped: there is no image.")
            return
        }
        let plan = RecipeClipboardPlan(step)
        var text: String?
        if plan.needsText {
            var found = payload.extractedText ?? ""
            if found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found = (try? await RecipeVision.text(of: payload.flattened() ?? payload.image)) ?? ""
                if !found.isEmpty {
                    payload.extractedText = found
                    context.payload = payload
                }
            }
            if let template = plan.customText {
                found = context.evaluator.evaluate(RecipeClipboardPlan.substitute(template, text: found), in: context.scope()).interpolationText
            }
            text = found
        }
        let chains = await MainActor.run { runtime.destinationChains?(context.recipe) ?? [] }
        var copies = RecipeDestinationCopies(chains: chains, steps: steps)
        let image = plan.mode == .textOnly ? payload : await copies.payload(for: "Clipboard", original: payload, in: context)
        let copied = text
        let result = await MainActor.run { () -> ExportResult in
            let capture = image.exportCapture()
            let state = runtime.flowState(context.executionId)
            state.holdMessages(of: capture, settings: runtime.app.settings)
            RecipePasteboard.write(plan.mode == .textOnly ? nil : capture, formats: plan.formats, text: copied)
            var result = ExportResult.succeeded(target: "Clipboard", clearsModified: false)
            result.exportedBy = "Clipboard"
            state.record(result)
            return result
        }
        context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: result.isSucceeded, target: "Clipboard"))
        if plan.mode == .textOnly {
            context.log((text ?? "").isEmpty ? "Warning: No OCR text detected to place on clipboard." : "Copied \(text?.count ?? 0) character(s) of text to clipboard.")
        } else {
            context.log("Copied capture to clipboard with \(plan.formats.count) format(s)" + ((text ?? "").isEmpty ? "." : " (including the text)."))
        }
    }
}

/// The recipes' own writes to the clipboard (they're recorded, so the Clipboard trigger doesn't take them for a copy).
@MainActor
enum RecipePasteboard {
    /// `capture` in `formats` and/or `text`; text only clears the image (upstream sets the text).
    static func write(_ capture: Capture?, formats: [RecipeClipboardPlan.Format], text: String?) {
        let item = NSPasteboardItem()
        if let capture {
            let rep = NSBitmapImageRep(cgImage: capture.image)
            rep.size = NSSize(width: CGFloat(capture.image.width) / capture.scale, height: CGFloat(capture.image.height) / capture.scale)
            let png = rep.representation(using: .png, properties: [:])
            if formats.contains(.png), let png { item.setData(png, forType: .png) }
            if formats.contains(.tiff), let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            if formats.contains(.html), let png {
                let width = Int(rep.size.width.rounded())
                let height = Int(rep.size.height.rounded())
                item.setString(DestinationSupport.htmlSnippet(png: png, width: width, height: height), forType: .html)
            }
        }
        if let text { item.setString(text, forType: .string) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        OwnPasteboardWrites.recordWrite(pasteboard)
    }

    static func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        OwnPasteboardWrites.recordWrite(pasteboard)
    }
}

// MARK: Notification

/// The Notification step's notification: the exports of the flow since the previous one, as one notification like a
/// capture's (`NotificationExportLog.present`: the settings, the thumbnail, QR codes on capture).
struct RecipeAppNotificationPresenter: RecipeNotificationPresenting {
    let runtime: RecipeRuntime

    func announce(_ exports: [RecipeExportOutcome], in context: RecipeFlowContext) async {
        guard let payload = context.payload else { return }
        await MainActor.run {
            let results = runtime.flowState(context.executionId).takeUnannounced()
            guard !results.isEmpty else { return }
            NotificationExportLog.present(results, of: payload.exportCapture(), settings: runtime.app.settings)
        }
    }
}

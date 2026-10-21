// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where a destination step exports to, and its per-node options (upstream `DestinationExportStep.cs`).
public enum RecipeDestinationPlan {
    /// The designations of the step (upstream `ResolveDestinationDesignations`): the alias step type's own one
    /// (SaveFile, Clipboard, Editor, Printer, Email, CustomDestination with `CustomDestinationId`), then the variable
    /// `OverrideDestinations` (a list or one name), then `DestinationDesignations`, else the settings' destinations.
    public static func designations(_ step: RecipeStepInvocation, overrides: JSONValue?, settings: [String]) -> [String] {
        let type = step.node.stepType
        if recipeEquals(type, WellKnownStepType.saveFile) { return ["FileNoDialog"] }
        if recipeEquals(type, WellKnownStepType.clipboard) { return ["Clipboard"] }
        if recipeEquals(type, WellKnownStepType.editor) { return ["Editor"] }
        if recipeEquals(type, WellKnownStepType.printer) { return ["Printer"] }
        if recipeEquals(type, WellKnownStepType.email) { return ["EMail"] }
        if recipeEquals(type, WellKnownStepType.customDestination),
           let custom = step.string("CustomDestinationId")?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            return [custom]
        }
        if let overrides, !overrides.isNull {
            let names = cleaned(overrides.asStrings ?? overrides.asString.map { [$0] } ?? [])
            if !names.isEmpty { return names }
        }
        let listed = cleaned(step.strings("DestinationDesignations") ?? [])
        if !listed.isEmpty { return listed }
        return cleaned(settings)
    }

    private static func cleaned(_ names: [String]) -> [String] {
        names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func isPicker(_ designation: String) -> Bool { recipeEquals(designation, "Picker") }

    /// An external command as the automatic steps name it (upstream's designation "External <command name>"): a plain
    /// "External" (the settings' destination) is the one command when there is exactly one; with several the destination
    /// asks which, so it stays "External". The command's name as written in the settings.
    public static func externalCommandDesignation(_ designation: String, commands: [String]) -> String {
        let parsed = destination(of: designation)
        guard parsed.destination == .externalCommand else { return designation }
        if let name = parsed.commandName, !name.isEmpty {
            return "External \(commands.first { recipeEquals($0, name) } ?? name)"
        }
        return commands.count == 1 ? "External \(commands[0])" : designation
    }

    /// The designation the automatic steps of a destination are stored under (RMANAGER's scope: "FileNoDialog", "EMail",
    /// "Windows10Share", …): an alias ("File", "SaveFile", "Mail", "Share", "OCR", "QRCode", "Notes") as the
    /// destination's own designation, an external command as "External <command name>"; anything else as it is.
    public static func canonicalDesignation(_ designation: String, commands: [String]) -> String {
        guard let destination = destination(of: designation).destination else { return designation }
        if destination == .externalCommand { return externalCommandDesignation(designation, commands: commands) }
        return RecipeDestinationDesignation.designation(for: destination)
    }

    /// The Mac destination of a designation and, for "External <name>", the command's name. Also the plain "External"
    /// that the settings' external command destination is called (`RecipeDestinationDesignation.designation(for:)`).
    public static func destination(of designation: String) -> (destination: CaptureDestination?, commandName: String?) {
        let trimmed = designation.trimmingCharacters(in: .whitespaces)
        if recipeEquals(trimmed, "External") { return (.externalCommand, nil) }
        let parsed = RecipeDestinationDesignation(trimmed)
        return (parsed.destination, parsed.externalCommandName)
    }

    /// `DestinationExportErrors`: "Designation: error; …" (upstream `DestinationDispatcher`).
    public static func errorsText(_ failures: [(designation: String, error: String)]) -> String {
        failures.map { "\($0.designation): \($0.error)" }.joined(separator: "; ")
    }

    /// The step's error for the first failed export, which error transitions route (upstream `DestinationExportException`).
    public static func failure(_ failures: [(designation: String, error: String)]) -> RecipeStepError? {
        guard let first = failures.first else { return nil }
        return RecipeStepError("Export to \(first.designation) failed: \(first.error)", errorType: "DestinationExportException")
    }
}

/// The file options of a destination step (upstream `ApplyCustomFileSettings`). Unset values come from the settings.
public struct RecipeFileExportOptions: Equatable, Sendable {
    public var saveDirectory: String?
    public var filenamePattern: String?
    public var format: ImageFormat?
    public var jpegQuality: Int?
    public var reduceColors: Bool?
    public var promptQuality: Bool?
    public var allowOverwrite: Bool?
    public var copyPathToClipboard: Bool?

    public init(_ step: RecipeStepInvocation) {
        func text(_ name: String) -> String? {
            guard step.isSet(name), let value = step.string(name)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }
        saveDirectory = text("SaveDirectory")
        filenamePattern = text("FilenamePattern")
        format = text("Format").flatMap(ImageFormat.init(fileExtension:))
        jpegQuality = step.isSet("JpegQuality") ? step.int("JpegQuality").map { min(max($0, 1), 100) } : nil
        reduceColors = step.isSet("ReduceColors") ? step.bool("ReduceColors") : nil
        promptQuality = step.isSet("PromptQuality") ? step.bool("PromptQuality") : nil
        allowOverwrite = step.isSet("AllowOverwrite") ? step.bool("AllowOverwrite") : nil
        copyPathToClipboard = step.isSet("CopyPathToClipboard") ? step.bool("CopyPathToClipboard") : nil
    }

    /// Whether `file` is inside `folder` once `..` and `.` are resolved (defence against a file name pattern whose
    /// values climb out of the folder; RSTEPS, S-M1).
    public static func isInside(_ file: URL, folder: URL) -> Bool {
        let parts = file.standardizedFileURL.pathComponents
        let root = folder.standardizedFileURL.pathComponents
        return parts.count > root.count && Array(parts.prefix(root.count)) == root
    }

    /// A file name pattern that names an absolute path ("/…" or "~…"): it may go anywhere, as the user wrote it.
    public static func isAbsolutePattern(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
    }

    /// Nothing set: the File destination saves exactly as without recipes.
    public var isEmpty: Bool { self == RecipeFileExportOptions() }

    private init() {}

    /// The `Destination.*` variables upstream sets before the export (their values, not the computed file).
    public func variables(defaultFormat: ImageFormat, defaultQuality: Int, defaultReduceColors: Bool) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if let promptQuality { result["Destination.PromptQuality"] = .bool(promptQuality) }
        if let allowOverwrite { result["Destination.AllowOverwrite"] = .bool(allowOverwrite) }
        if let copyPathToClipboard { result["Destination.CopyPathToClipboard"] = .bool(copyPathToClipboard) }
        if jpegQuality != nil || reduceColors != nil {
            result["Destination.SurfaceOutputSettings"] = .object([
                "Format": .string((format ?? defaultFormat).rawValue),
                "JpegQuality": .number(Double(jpegQuality ?? defaultQuality)),
                "ReduceColors": .bool(reduceColors ?? defaultReduceColors)
            ])
        }
        return result
    }
}

/// The print options of a destination step's printer (upstream `DestinationExportStep.cs:167-191`, its `PrintOptions`):
/// for this one print, the settings stay as they are. Unset values come from the settings.
public enum RecipePrintOptions {
    /// `base` (the settings' print options) with the step's `ShowPrintDialog`, `AllowRotate`, `AllowEnlarge`,
    /// `AllowShrink`, `Center`, `PrintFooter`, `FooterPattern` and `ColorMode` (Color, Grayscale or Monochrome) over it;
    /// nil when the step sets none of them.
    public static func apply(_ step: RecipeStepInvocation, to base: PrintSettings) -> PrintSettings? {
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

    /// `options` with the print options an administrator locked (a configuration profile, `ManagedPolicy`) put back:
    /// a recipe's options and the dialog of one print can't print with other values than Settings › Printer can.
    /// `settings` are the settings in effect, which `options` replace for this print.
    public static func enforcingLocks(_ options: PrintSettings, policy: ManagedPolicy, settings: AppSettings) -> PrintSettings {
        guard policy.isLocked("printing") else { return options }
        var forThisPrint = settings
        forThisPrint.printing = options
        return policy.effective(forThisPrint).printing
    }
}

/// The Clipboard step (upstream `ExecuteClipboardExportAsync`): what goes on the clipboard and in which formats.
public struct RecipeClipboardPlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case imageOnly, textOnly, imageAndText
    }

    /// The Mac's pasteboard flavours for upstream's formats: PNG; DIB, DIBV5 and Bitmap as TIFF (the Mac's bitmap
    /// flavour); HTML and HTML with a data URL as an HTML snippet with the PNG inline.
    public enum Format: String, Equatable, Sendable, CaseIterable {
        case png, tiff, html
    }

    public var mode: Mode
    public var formats: [Format]
    /// `ClipboardCustomText` as written (its `${ocr_text}` / `${payload.text}` are the step's to fill in).
    public var customText: String?

    public init(_ step: RecipeStepInvocation) {
        let modeName = step.string("ClipboardMode")?.trimmingCharacters(in: .whitespaces) ?? "ImageOnly"
        let alsoText = step.bool("ClipboardFormatText") ?? false
        if recipeEquals(modeName, "TextOnly") {
            mode = .textOnly
        } else if recipeEquals(modeName, "ImageAndText") || alsoText {
            mode = .imageAndText
        } else {
            mode = .imageOnly
        }
        var formats: [Format] = []
        if step.bool("ClipboardFormatPNG") ?? true { formats.append(.png) }
        let bitmap = (step.bool("ClipboardFormatDIB") ?? true) || (step.bool("ClipboardFormatDIBV5") ?? false)
            || (step.bool("ClipboardFormatBitmap") ?? false)
        if bitmap { formats.append(.tiff) }
        // Upstream's own default list has HTML on (ExecuteClipboardExportAsync), the contract's not: the step's code wins.
        if (step.bool("ClipboardFormatHTML") ?? true) || (step.bool("ClipboardFormatHTMLDataUrl") ?? false) { formats.append(.html) }
        if formats.isEmpty { formats = [.png] }
        self.formats = formats
        let raw = step.node.parameters["ClipboardCustomText"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        customText = raw.isEmpty ? nil : raw
    }

    public var needsText: Bool { mode != .imageOnly }

    /// `${ocr_text}` and `${payload.text}` replaced by the text (upstream replaces both before filling the variables).
    public static func substitute(_ template: String, text: String) -> String {
        var result = template
        for token in ["${ocr_text}", "${payload.text}"] {
            while let range = result.range(of: token, options: .caseInsensitive) {
                result.replaceSubrange(range, with: text)
            }
        }
        return result
    }
}

/// Where an export goes as the app knows it: a designation and, for entries of the picker, what was picked (a printer,
/// an issue, an open document).
public struct RecipeExportTarget: @unchecked Sendable {
    public var designation: String
    /// The app's own value for the target (its `DestinationTarget`); nil for a plain designation.
    public var detail: Any?

    public init(designation: String, detail: Any? = nil) {
        self.designation = designation
        self.detail = detail
    }
}

/// The app's side of the destination steps (`RecipeDestinationDispatcher`).
public protocol RecipeExporting: Sendable {
    /// Before the exports (upstream `ApplyCustomFileSettings`): sets `Destination.*` variables it computes (the file of
    /// `SaveDirectory`).
    func prepare(_ step: RecipeStepInvocation, payload: RecipePayload, in context: RecipeFlowContext) async
    /// The target of a designation; nil when it isn't a destination here or an administrator turned it off (skipped).
    func target(for designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async -> RecipeExportTarget?
    /// The destination picker; nil when it was closed.
    func pick(_ payload: RecipePayload, in context: RecipeFlowContext) async -> RecipeExportTarget?
    /// One export. Records the result for the Notification step (the dispatcher records the outcome in `context.exports`).
    func export(_ payload: RecipePayload, to target: RecipeExportTarget, step: RecipeStepInvocation,
                in context: RecipeFlowContext) async -> ExportResult
}

/// The Destinations step and its aliases (upstream `DestinationExportStep` + `DestinationDispatcher`): the designations
/// one after the other in the recipe's order (a later one may use an earlier one's result), the picker until an export
/// succeeds, the BeforeDestination automatic steps on a copy per combination of them, and the failed exports at the end
/// as `DestinationExportErrors` and a `DestinationExportException` for error transitions.
public struct RecipeDestinationDispatcher: RecipeStepExecutor {
    let exporter: any RecipeExporting
    let steps: RecipeStepRegistry
    /// The automatic steps for the destinations of the running recipe (RMANAGER's composer through the runtime).
    let chains: @Sendable (CaptureRecipe) async -> [RecipeDestinationChain]
    /// The settings' destinations as designations.
    let settingsDestinations: @Sendable () -> [String]

    public init(exporter: any RecipeExporting, steps: RecipeStepRegistry,
                chains: @escaping @Sendable (CaptureRecipe) async -> [RecipeDestinationChain] = { _ in [] },
                settingsDestinations: @escaping @Sendable () -> [String]) {
        self.exporter = exporter
        self.steps = steps
        self.chains = chains
        self.settingsDestinations = settingsDestinations
    }

    public func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        context.state = .exporting
        guard let payload = context.payload else {
            context.log("Destinations skipped: there is no image.")
            return
        }
        await exporter.prepare(step, payload: payload, in: context)
        let designations = RecipeDestinationPlan.designations(step, overrides: context[variable: "OverrideDestinations"],
                                                               settings: settingsDestinations())
        let allChains = await chains(context.recipe)
        var copies = RecipeDestinationCopies(chains: allChains, steps: steps)
        if designations.contains(where: RecipeDestinationPlan.isPicker) {
            await pickAndExport(payload, step: step, copies: &copies, in: context)
            return
        }
        var targets: [RecipeExportTarget] = []
        for designation in designations {
            if let target = await exporter.target(for: designation, step: step, in: context) {
                targets.append(target)
            } else {
                context.log("Warning: no destination '\(designation)' here, skipped.")
            }
        }
        context.log("Exporting capture to \(targets.count) destination(s): \(targets.map(\.designation).joined(separator: ", "))")
        var failures: [(designation: String, error: String)] = []
        for target in targets {
            try Task.checkCancellation()
            let copy = await copies.payload(for: target.designation, original: payload, in: context)
            let result = await exporter.export(copy, to: target, step: step, in: context)
            record(result, of: target.designation, in: context)
            if result.status == .failed { failures.append((target.designation, result.error ?? "unknown error")) }
        }
        if let error = RecipeDestinationPlan.failure(failures) {
            context[variable: "DestinationExportErrors"] = .string(RecipeDestinationPlan.errorsText(failures))
            throw error
        }
    }

    /// The picker until an export succeeds or it is closed; the automatic steps run for the picked destination.
    private func pickAndExport(_ payload: RecipePayload, step: RecipeStepInvocation, copies: inout RecipeDestinationCopies,
                               in context: RecipeFlowContext) async {
        while !Task.isCancelled {
            guard let target = await exporter.pick(payload, in: context) else {
                context.log("The destination picker was closed.")
                return
            }
            let copy = await copies.payload(for: target.designation, original: payload, in: context)
            let result = await exporter.export(copy, to: target, step: step, in: context)
            record(result, of: target.designation, in: context)
            if result.isSucceeded { return }
        }
    }

    /// Every export but a declined one goes into the flow's export log (upstream `RecordExport`).
    private func record(_ result: ExportResult, of designation: String, in context: RecipeFlowContext) {
        guard result.status != .declined else { return }
        context.exports.add(RecipeExportOutcome(designation: designation, succeeded: result.isSucceeded,
                                                target: result.fileURL?.path ?? result.target, uri: result.link,
                                                errorMessage: result.error))
        context.log(result.isSucceeded ? "Exported to \(designation)." : "Export to \(designation) failed: \(result.error ?? "")")
    }
}

/// The copies of the capture changed by the BeforeDestination automatic steps (upstream `ExportWithChainsAsync`):
/// destinations with the same automatic steps share one copy, a failed automatic step exports the original.
public struct RecipeDestinationCopies: Sendable {
    let chains: [RecipeDestinationChain]
    let steps: RecipeStepRegistry
    private var made: [String: RecipePayload?] = [:]

    public init(chains: [RecipeDestinationChain], steps: RecipeStepRegistry) {
        self.chains = chains
        self.steps = steps
    }

    /// The chains that run for a designation, in their order.
    public func chains(for designation: String) -> [RecipeDestinationChain] {
        chains.filter { $0.runs(for: designation) }
    }

    /// The key of a combination of chains: their extension ids.
    public static func key(_ chains: [RecipeDestinationChain]) -> String {
        chains.map(\.extensionId).joined(separator: "|")
    }

    public mutating func payload(for designation: String, original: RecipePayload, in context: RecipeFlowContext) async -> RecipePayload {
        let applicable = chains(for: designation)
        guard !applicable.isEmpty else { return original }
        let key = Self.key(applicable)
        if let cached = made[key] { return cached ?? original }
        let copy = await Self.run(applicable, on: original, in: context, steps: steps, forWhat: "destination '\(designation)'")
        made[key] = .some(copy)
        return copy ?? original
    }

    /// Runs the chains on a copy of `payload` (upstream `RunChainsOnCopyAsync`); nil when one failed.
    public static func run(_ chains: [RecipeDestinationChain], on payload: RecipePayload, in context: RecipeFlowContext,
                           steps: RecipeStepRegistry, forWhat: String) async -> RecipePayload? {
        var current = payload
        let engine = RecipeFlowEngine(steps: steps)
        for chain in chains {
            let copy = RecipeFlowContext(recipe: chain.flow, trigger: context.trigger, environment: context.environment,
                                         optionValues: context.optionValues, output: context.output, executionId: context.executionId)
            for member in context.variables { copy[variable: member.key] = member.value }
            copy.payload = current
            copy.isPayloadPreSupplied = context.isPayloadPreSupplied
            context.log("Running automatic step '\(chain.extensionName ?? chain.extensionId)' for \(forWhat).")
            await engine.execute(copy)
            guard !copy.isAborted, let changed = copy.payload else {
                context.log("Warning: automatic step '\(chain.extensionId)' failed for \(forWhat) (\(copy.abortReason ?? "")), the capture is used without it.")
                return nil
            }
            current = changed
        }
        return current
    }
}

// MARK: Notification

/// The app's side of the Notification step: shows (or drops) the exports since the previous Notification step.
public protocol RecipeNotificationPresenting: Sendable {
    /// Shows one notification for `exports`; `context` gives the capture.
    func announce(_ exports: [RecipeExportOutcome], in context: RecipeFlowContext) async
}

/// Upstream `NotificationStep`: `ShowNotification` variable, parameter, else the setting; the exports since the
/// previous Notification step (of every destination step and branch) in one notification. Sets
/// `EnableCompletionNotification` and `Notification.AnnouncedExports` (how many exports the flow's notifications showed,
/// for RUI's failure message; the count of the whole flow, kept in its export log).
public struct RecipeNotificationExecutor: RecipeStepExecutor {
    public static let announcedExportsVariable = RecipeExportLog.announcedExportsVariable

    let presenter: any RecipeNotificationPresenting

    public init(presenter: any RecipeNotificationPresenting) {
        self.presenter = presenter
    }

    /// The step's contract plus `Notification.AnnouncedExports` (registered with `register(contract:executor:)`).
    public static var contract: StepContract {
        var contract = StepContractCatalog.builtIn.contract(for: WellKnownStepType.notification)!
        contract.outputVariables.append(VariableContract(announcedExportsVariable, .integer,
                                                         description: "How many exports the notifications of this flow showed so far"))
        return contract
    }

    public func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let setting = context.environment.configValue("showtraynotification")?.asBool ?? true
        let show = step.resolved("ShowNotification", overrideVariable: "ShowNotification", in: context)?.asBool ?? setting
        context[variable: "EnableCompletionNotification"] = .bool(show)
        let exports = context.exports.takeUnnotified()
        var shown = 0
        if show, !exports.isEmpty {
            await presenter.announce(exports, in: context)
            shown = exports.count
        }
        // Parallel branches and forwarded recipes add to one count (a copy of the variable would lose theirs).
        let announced = context.exports.recordAnnounced(shown)
        context[variable: Self.announcedExportsVariable] = .number(Double(announced))
    }
}

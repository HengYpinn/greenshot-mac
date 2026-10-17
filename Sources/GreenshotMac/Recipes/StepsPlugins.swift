// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The steps of upstream's plug-ins, built in on the Mac: Jira, Confluence, Box, Dropbox, Office, Pdf (the plug-ins'
/// Recipes/*Step.cs). Each exports like its destination and records the export for the Notification step; a failed
/// upload is shown and recorded, and the flow goes on (upstream logs it and goes on).
@MainActor
enum RecipeStepExports {
    /// The capture for the export; the destinations' own messages wait for the flow's Notification step from now on.
    static func begin(_ payload: RecipePayload, context: RecipeFlowContext, runtime: RecipeRuntime) -> Capture {
        let capture = payload.exportCapture()
        runtime.flowState(context.executionId).holdMessages(of: capture, settings: runtime.app.settings)
        return capture
    }

    /// Records the export (a declined one isn't).
    static func finish(_ result: ExportResult, designation: String, context: RecipeFlowContext, runtime: RecipeRuntime) {
        var result = result
        if result.exportedBy == nil { result.exportedBy = designation }
        runtime.flowState(context.executionId).record(result)
        guard result.status != .declined else { return }
        context.exports.add(RecipeExportOutcome(designation: designation, succeeded: result.isSucceeded,
                                                target: result.fileURL?.path ?? result.target, uri: result.link,
                                                errorMessage: result.error))
    }

    /// An upload's format and quality: the step's, else the destination's settings.
    static func uploadFormat(_ step: RecipeStepInvocation, default format: UploadFormat) -> UploadFormat {
        guard let name = step.string("Format")?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return format }
        return UploadFormat(rawValue: name == "jpeg" ? "jpg" : name) ?? format
    }

    /// `Uploads.run` as an async call.
    static func run(_ failureTitle: String, progress: String, _ operation: @escaping @MainActor () async throws -> ExportResult) async -> ExportResult {
        await withCheckedContinuation { continuation in
            Uploads.run(failureTitle, progress: progress, completion: { continuation.resume(returning: $0) }, operation)
        }
    }
}

/// Upstream `JiraStep`: `IssueKey` (else the variable `Jira.IssueKey`) attaches without asking, with the step's format;
/// without a key the Jira destination asks. Sets `Jira.UploadUrl` and `Jira.IssueKey`.
struct RecipeJiraExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else {
            context.log("JiraStep: No surface available to upload.")
            return
        }
        context.state = .exporting
        let given = step.string("IssueKey")?.trimmingCharacters(in: .whitespaces)
        let key = (given?.isEmpty == false ? given : nil) ?? context[variable: "Jira.IssueKey"]?.asString
        let result = await Self.export(payload, key: key, step: step, context: context, runtime: runtime)
        if result.isSucceeded {
            if let link = result.link { context[variable: "Jira.UploadUrl"] = .string(link.absoluteString) }
            if let target = result.target { context[variable: "Jira.IssueKey"] = .string(target) }
        }
    }

    @MainActor
    private static func export(_ payload: RecipePayload, key: String?, step: RecipeStepInvocation, context: RecipeFlowContext,
                               runtime: RecipeRuntime) async -> ExportResult {
        let app = runtime.app
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        var result: ExportResult
        if let key, !key.trimmingCharacters(in: .whitespaces).isEmpty {
            let filled = FilenamePattern.fill(key, context: app.settings.patternContext(title: capture.title, date: capture.date,
                                                                                       consumeNumber: false), filenameSafe: false)
            result = await attach(capture, key: filled, step: step, settings: app.settings, saver: app.saver)
        } else {
            context.log("JiraStep: No issue key specified; delegating to Jira destination.")
            result = await RecipeAppExporter.perform(.destination(.jira), capture: capture, output: app.output)
        }
        RecipeStepExports.finish(result, designation: "Jira", context: context, runtime: runtime)
        return result
    }

    @MainActor
    private static func attach(_ capture: Capture, key: String, step: RecipeStepInvocation, settings: SettingsStore,
                               saver: ImageSaver) async -> ExportResult {
        let normalized = JiraClient.normalizedKey(key)
        guard JiraClient.isIssueKey(normalized) else { return .failed("“\(key)” is no Jira issue key.", target: key) }
        guard let site = await AtlassianSignIn.ready(.jira, settings: settings) else { return .declined }
        let s = settings.value
        let format = RecipeStepExports.uploadFormat(step, default: s.jira.uploadFormat)
        let quality = step.int("JpegQuality").map { min(max($0, 1), 100) } ?? s.jira.jpegQuality
        let reduce = step.bool("ReduceColors") ?? s.jira.reduceColors
        let file: UploadFile
        do {
            file = try Uploads.file(capture, name: Uploads.suggestedName(for: capture, settings: settings, format: format), format: format,
                                    quality: quality, reduceColors: reduce)
        } catch {
            return .failed(error.localizedDescription)
        }
        let client = JiraClient(site: site, http: Uploads.http)
        return await RecipeStepExports.run("The upload to Jira failed", progress: "Transferring data to Jira, please wait…") {
            _ = try await client.attach(file, to: normalized)
            settings.update { $0.jira.remember(issueKey: normalized) }
            let url = client.browseURL(for: normalized)
            saver.notify("Attached \(file.name) to \(normalized)", detail: "Click to open the issue") { NSWorkspace.shared.open(url) }
            return .succeeded(link: url, target: normalized)
        }
    }
}

/// Upstream `ConfluenceStep`: `PageId` attaches to that page without asking; without it the Confluence destination asks.
/// Sets `Confluence.PageId` and `Confluence.UploadUrl`.
struct RecipeConfluenceExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else {
            context.log("ConfluenceStep: No surface available to upload.")
            return
        }
        context.state = .exporting
        let pageId = step.string("PageId")?.trimmingCharacters(in: .whitespaces) ?? ""
        let result = await Self.export(payload, pageId: pageId, step: step, context: context, runtime: runtime)
        if result.isSucceeded {
            if !pageId.isEmpty { context[variable: "Confluence.PageId"] = .string(pageId) }
            if let link = result.link { context[variable: "Confluence.UploadUrl"] = .string(link.absoluteString) }
        }
    }

    @MainActor
    private static func export(_ payload: RecipePayload, pageId: String, step: RecipeStepInvocation, context: RecipeFlowContext,
                               runtime: RecipeRuntime) async -> ExportResult {
        let app = runtime.app
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let result: ExportResult
        if pageId.isEmpty {
            result = await RecipeAppExporter.perform(.destination(.confluence), capture: capture, output: app.output)
        } else {
            result = await attach(capture, pageId: pageId, step: step, settings: app.settings, saver: app.saver)
        }
        RecipeStepExports.finish(result, designation: "Confluence", context: context, runtime: runtime)
        return result
    }

    @MainActor
    private static func attach(_ capture: Capture, pageId: String, step: RecipeStepInvocation, settings: SettingsStore,
                               saver: ImageSaver) async -> ExportResult {
        guard let site = await AtlassianSignIn.ready(.confluence, settings: settings) else { return .declined }
        let s = settings.value
        let format = RecipeStepExports.uploadFormat(step, default: s.confluence.uploadFormat)
        let quality = step.int("JpegQuality").map { min(max($0, 1), 100) } ?? s.confluence.jpegQuality
        let reduce = step.bool("ReduceColors") ?? s.confluence.reduceColors
        let file: UploadFile
        do {
            file = try Uploads.file(capture, name: Uploads.suggestedName(for: capture, settings: settings, format: format), format: format,
                                    quality: quality, reduceColors: reduce)
        } catch {
            return .failed(error.localizedDescription)
        }
        let client = ConfluenceClient(site: site, http: Uploads.http)
        return await RecipeStepExports.run("The upload to Confluence failed", progress: "Transferring data to Confluence, please wait…") {
            let page = try await client.page(id: pageId)
            let attachments = try await client.attach(file, toPage: page.id)
            settings.update { $0.confluence.remember(page: page) }
            let pageURL = site.isOnSite(page.url) ? page.url : nil
            let download = attachments.first?.downloadURL.flatMap { site.isOnSite($0) ? $0 : nil }
            saver.notify("Attached \(file.name) to “\(page.title)”", detail: "Click to open the page") {
                if let pageURL { NSWorkspace.shared.open(pageURL) }
            }
            return .succeeded(link: download ?? pageURL, target: page.title)
        }
    }
}

/// Upstream `BoxStep` / `DropboxStep`: the upload of the destination (its account and folder); `Box.UploadUrl` /
/// `Dropbox.UploadUrl`.
struct RecipeCloudExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime
    let destination: CaptureDestination

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else {
            context.log("\(name)Step: No surface available to upload.")
            return
        }
        context.state = .exporting
        let result = await Self.export(payload, to: destination, name: name, context: context, runtime: runtime)
        if result.isSucceeded, let link = result.link { context[variable: "\(name).UploadUrl"] = .string(link.absoluteString) }
    }

    private var name: String { destination == .box ? "Box" : "Dropbox" }

    @MainActor
    private static func export(_ payload: RecipePayload, to destination: CaptureDestination, name: String, context: RecipeFlowContext,
                               runtime: RecipeRuntime) async -> ExportResult {
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let result = await RecipeAppExporter.perform(.destination(destination), capture: capture, output: runtime.app.output)
        RecipeStepExports.finish(result, designation: name, context: context, runtime: runtime)
        return result
    }
}

/// Upstream `OfficeStep`: Word (default), Excel, PowerPoint, Outlook, OneNote (Notes on the Mac) through the Office
/// destination (a new document, or the open one it offers).
struct RecipeOfficeExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else {
            context.log("OfficeStep: No surface available to export.")
            return
        }
        context.state = .exporting
        let name = step.string("Application")?.trimmingCharacters(in: .whitespaces) ?? "Word"
        let destination = Self.destination(name)
        context.log("Exporting capture to Office application (\(name))...")
        await Self.export(payload, to: destination, context: context, runtime: runtime)
    }

    static func destination(_ name: String) -> CaptureDestination {
        switch name.lowercased() {
        case "excel": return .excel
        case "powerpoint": return .powerpoint
        case "outlook": return .outlook
        case "onenote", "notes": return .notes
        default: return .word
        }
    }

    @MainActor
    private static func export(_ payload: RecipePayload, to destination: CaptureDestination, context: RecipeFlowContext,
                               runtime: RecipeRuntime) async {
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let result = await RecipeAppExporter.perform(.destination(destination), capture: capture, output: runtime.app.output)
        RecipeStepExports.finish(result, designation: RecipeDestinationDesignation.designation(for: destination), context: context,
                                 runtime: runtime)
    }
}

/// Upstream `PdfStep`: the PDF settings with the step's page size, size and margins (millimetres), scaling; the save
/// dialog (`ShowSaveDialog`, default on) or the output folder. Sets `Pdf.FilePath`.
struct RecipePdfExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else {
            context.log("PdfStep: No surface available to export.")
            return
        }
        context.state = .exporting
        let result = await Self.export(payload, step: step, context: context, runtime: runtime)
        if result.isSucceeded, let file = result.fileURL { context[variable: "Pdf.FilePath"] = .string(file.path) }
    }

    /// The PDF settings with the step's values; the sizes are millimetres in the step.
    static func settings(_ step: RecipeStepInvocation, base: PDFSettings) -> PDFSettings {
        var pdf = base
        if let name = step.string("PageSize")?.trimmingCharacters(in: .whitespaces).lowercased(), let size = PDFSettings.PageSize(rawValue: name) {
            pdf.pageSize = size
        }
        let millimetres = ["PageWidthMm", "PageHeightMm", "MarginTopMm", "MarginBottomMm", "MarginLeftMm", "MarginRightMm"]
        if millimetres.contains(where: step.isSet) {
            // The step's values are millimetres: the settings' values in their unit become millimetres first.
            let factor = pdf.unit.points / PDFSettings.Unit.mm.points
            pdf.customWidth *= factor
            pdf.customHeight *= factor
            pdf.marginTop *= factor
            pdf.marginBottom *= factor
            pdf.marginLeft *= factor
            pdf.marginRight *= factor
            pdf.unit = .mm
            func set(_ name: String, _ keyPath: WritableKeyPath<PDFSettings, Double>) {
                if step.isSet(name), let value = step.double(name) { pdf[keyPath: keyPath] = max(value, 0) }
            }
            set("PageWidthMm", \.customWidth)
            set("PageHeightMm", \.customHeight)
            set("MarginTopMm", \.marginTop)
            set("MarginBottomMm", \.marginBottom)
            set("MarginLeftMm", \.marginLeft)
            set("MarginRightMm", \.marginRight)
        }
        switch step.string("ScalingMode")?.lowercased() {
        case "fittopage": pdf.scaling = .fitToPage
        case "onlyshrinktofit": pdf.scaling = .shrinkToFit
        default: break
        }
        return pdf
    }

    @MainActor
    private static func export(_ payload: RecipePayload, step: RecipeStepInvocation, context: RecipeFlowContext,
                               runtime: RecipeRuntime) async -> ExportResult {
        let app = runtime.app
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let pdf = settings(step, base: app.settings.value.pdf)
        var url: URL
        if step.bool("ShowSaveDialog") ?? true {
            let panel = NSSavePanel()
            panel.title = "Save Screenshot as PDF"
            panel.allowedContentTypes = [.pdf]
            guard let chosen = app.saver.runSavePanel(panel, title: capture.title, date: capture.date, fileExtension: "pdf") else {
                RecipeStepExports.finish(.declined, designation: "Pdf", context: context, runtime: runtime)
                return .declined
            }
            url = chosen
        } else {
            url = app.saver.defaultURL(title: capture.title, date: capture.date, fileExtension: "pdf")
            if !app.settings.value.allowOverwrite { url = DestinationSupport.uniqueURL(for: url) }
        }
        var result: ExportResult
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PdfLayout.write(capture.image, scale: capture.scale, settings: pdf, title: capture.title, to: url)
            app.saver.notifySaved(url, copyPath: false)
            result = .succeeded(fileURL: url)
        } catch {
            log.error("A recipe could not save the PDF \(url.lastPathComponent)", error: error)
            result = .failed(error.localizedDescription, target: url.lastPathComponent)
        }
        RecipeStepExports.finish(result, designation: "Pdf", context: context, runtime: runtime)
        return result
    }
}

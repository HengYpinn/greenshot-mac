// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import GreenshotCore

/// AI tools in the running app (upstream `Ai/AiToolsIpcExtension.cs`, `AiToolAccess`, `AiToolIpcHandler`,
/// `AiRecipeIpcHandler`): the commands of greenshot-mcp, the opt-in and per-program consent, window ids, the excluded
/// applications in AI tools' captures, the notification on every capture, and `tools_changed` for greenshot-mcp when
/// the recipes or the switch change.
@MainActor
final class AIToolsCenter: ObservableObject {
    /// The running app's (the Settings tab asks it; nil in `--snapshot` and before the automation started).
    private(set) static var shared: AIToolsCenter?

    let consent = AIToolConsent()
    let windowRefs = AIWindowRefs(ownerOf: { AIToolsWindows.owner(of: $0) })
    let captureGuard: AIToolsCaptureGuard
    /// "Not allowed until restart" in Settings › AI Tools.
    @Published private(set) var deniedClients: [String] = []
    private unowned let app: AppDelegate
    private let broadcast: (JSONObject) -> Void
    private let identity = AIToolsClientIdentity()
    private var proposals: AIRecipeProposals?
    private var recipesObservation: RecipeObservation?
    private var lastSettings: AIToolsSettings
    private let log = Log("AITools")

    init(app: AppDelegate, broadcast: @escaping (JSONObject) -> Void) {
        self.app = app
        self.broadcast = broadcast
        lastSettings = app.settings.value.aiTools
        captureGuard = AIToolsCaptureGuard(excluded: app.settings.value.aiTools.excludedApplications)
    }

    /// At launch, from the automation's start: the commands, the capture guard on the recipes, the change signals.
    func start(table: IPCCommandTable) {
        Self.shared = self
        AIToolsCommands.register(in: table, app: app, center: self)
        let recipes = app.recipes
        recipes.aiToolCaptureGuard = captureGuard
        recipesObservation = recipes.addChangeObserver { [weak self] in self?.toolsChanged() }
        app.settings.onChange(of: \AppSettings.aiTools) { [weak self] settings in
            guard let self else { return }
            captureGuard.excludedApplications = settings.excludedApplications
            if settings.enabled != lastSettings.enabled { toolsChanged() }
            lastSettings = settings
        }
    }

    /// greenshot-mcp syncs its tools at once.
    private func toolsChanged() {
        broadcast(["event": .string("tools_changed")])
    }

    // MARK: Access

    /// Upstream `AiToolsIpcExtension.CheckAccessAsync`: the opt-in switches, then the user's consent for the program
    /// behind greenshot-mcp (asked the first time). Nil: go ahead.
    func refusal(of command: String, context: IPCReplyContext) async -> String? {
        let settings = app.settings.value.aiTools
        if let refusal = AIToolAccess.optInRefusal(command: command, source: context.source, settings: settings) {
            log.warn("[SECURITY] IPC command rejected: '\(command)' from source '\(context.source.rawValue)': \(refusal)")
            return refusal
        }
        guard AIToolAccess.requiresConsent(command: command, source: context.source) else { return nil }
        let client: AIToolClient
        switch identity.client(of: context) {
        case .success(let identified): client = identified
        case .failure(let error):
            log.warn("[SECURITY] IPC command rejected: '\(command)' from source '\(context.source.rawValue)': \(error.message)")
            return error.message
        }
        let managed = app.settings.isLocked(\AppSettings.aiTools.allowedClients)
        let allowed = await consent.ensureAllowed(client, settings: { [app] in app.settings.value.aiTools }, managed: managed,
                                                  prompt: { await AIToolsConsentPanel.ask($0) },
                                                  allow: { [app] path in app.settings.update { $0.aiTools.allowedClients.append(path) } })
        deniedClients = consent.deniedClients
        guard allowed else {
            log.warn("[SECURITY] IPC command rejected: '\(command)' from source 'mcp', the user did not allow \(client.logText).")
            return managed ? AIToolAccess.managedMessage : AIToolAccess.notAllowedMessage
        }
        return nil
    }

    /// The AI tool of a request (cached per greenshot-mcp session).
    func client(of context: IPCReplyContext) -> Result<AIToolClient, AIToolError> {
        identity.client(of: context)
    }

    /// The signer text of a program in the allowed list (the Settings tab).
    func signer(of path: String) -> String? {
        identity.signer(of: path)
    }

    // MARK: Settings › AI Tools

    /// "Allow" of a program that was refused in this run.
    func allowDenied(_ path: String) {
        consent.forgetDenied(path)
        app.settings.update { settings in
            if !settings.aiTools.allowedClients.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
                settings.aiTools.allowedClients.append(path)
            }
        }
        deniedClients = consent.deniedClients
    }

    /// "Ask Again": the next request of the program asks.
    func askAgain(_ path: String) {
        consent.forgetDenied(path)
        deniedClients = consent.deniedClients
    }

    // MARK: Proposals

    /// The proposals of AI tools (one at a time, rejections remembered until the app quits).
    func recipeProposals(_ recipes: RecipeRuntime) -> AIRecipeProposals {
        if let proposals { return proposals }
        let made = AIRecipeProposals(library: recipes.library, folder: recipes.recipesFolder.appendingPathComponent("AI", isDirectory: true))
        proposals = made
        return made
    }

    // MARK: Notification

    /// Upstream `NotifyCapture`: every capture of an AI tool shows a notification (`notifyOnCapture`).
    func notifyCapture(client: String?, what: String) {
        guard app.settings.value.aiTools.notifyOnCapture else { return }
        Toast.show(AIToolAccess.captureNotice(client: client, what: what), kind: .info)
    }
}

/// The handlers of greenshot-mcp's commands (upstream `AiToolIpcHandler`, `AiRecipeIpcHandler`). The dispatcher already
/// checked the source (only `mcp`), the opt-in and the consent; they run on the main actor and wait for the recipes.
@MainActor
enum AIToolsCommands {
    static func register(in table: IPCCommandTable, app: AppDelegate, center: AIToolsCenter) {
        table.register(IPCCommand.listWindows) { [app, center] context in await listWindows(app, center, context) }
        table.register(IPCCommand.listAITools) { [app] context in await listAITools(app, context) }
        table.register(IPCCommand.runAITool) { [app, center] context in await runAITool(app, center, context) }
        table.register(IPCCommand.recipeCatalog) { [app] context in
            await recipeCommand(app) { library in AIRecipeCatalog.catalogReply(recipeId: context.envelope.parameter("recipe"), library: library) }
        }
        table.register(IPCCommand.validateRecipe) { [app] context in
            await recipeCommand(app) { library in AIRecipeCatalog.validateReply(json: context.envelope.parameter("recipe"), library: library) }
        }
        table.register(IPCCommand.proposeRecipe) { [app, center] context in await proposeRecipe(app, center, context) }
    }

    /// LIST_WINDOWS: the windows with ids for Window arguments, and the displays; excluded applications left out.
    private static func listWindows(_ app: AppDelegate, _ center: AIToolsCenter, _ context: IPCReplyContext) -> IPCReply {
        let client: AIToolClient
        switch center.client(of: context) {
        case .success(let identified): client = identified
        case .failure: return .error(AIToolAccess.notAllowedMessage)
        }
        return AIToolsWindows.listReply(client: client, refs: center.windowRefs, excluded: app.settings.value.aiTools.excludedApplications)
    }

    /// LIST_AI_TOOLS: the recipes with an AI tool trigger.
    private static func listAITools(_ app: AppDelegate, _ context: IPCReplyContext) async -> IPCReply {
        let recipes = app.recipes
        await recipes.whenLoaded()
        return AIToolCatalog.listReply(AIToolCatalog.tools(in: recipes.library, client: context.origin ?? ""))
    }

    /// RUN_AI_TOOL: runs the tool's recipe with the arguments (window ids resolved for this AI tool) and replies with its
    /// result, picture and text. Everything an AI tool captures goes through such a recipe.
    private static func runAITool(_ app: AppDelegate, _ center: AIToolsCenter, _ context: IPCReplyContext) async -> IPCReply {
        let client: AIToolClient
        switch center.client(of: context) {
        case .success(let identified): client = identified
        case .failure: return .error(AIToolAccess.notAllowedMessage)
        }
        let recipes = app.recipes
        await recipes.whenLoaded()
        let name = context.envelope.recipe?.trimmingCharacters(in: .whitespaces) ?? ""
        let tools = AIToolCatalog.tools(in: recipes.library, client: client.displayName)
        guard let tool = AIToolCatalog.tool(named: name, in: tools) else {
            return .error("There is no AI tool '\(name)' (anymore), the tools are the recipes with an AI tool trigger.")
        }
        let excluded = app.settings.value.aiTools.excludedApplications
        let prepared = AIToolCatalog.prepareArguments(tool, supplied: context.envelope.parameters) { reference in
            switch center.windowRefs.resolve(scope: client.scopeKey, reference: reference) {
            case .failure(let error):
                return .failure(error)
            case .success(let window):
                // The exclusion list may have changed since the window was listed
                if let info = AIToolsWindows.window(window), AIToolExclusion.isExcluded(names: info.names, excluded: excluded) {
                    return .failure(AIToolError("windows of '\(info.owner)' are excluded from AI tools."))
                }
                return .success(window)
            }
        }
        let arguments: [String: String]
        switch prepared {
        case .success(let values): arguments = values
        case .failure(let error): return .error(error.message, exitCode: IPCExitCode.usage)
        }
        var request: RecipeRunRequest
        switch AIToolCatalog.runRequest(tool, arguments: arguments, library: recipes.library, client: client.displayName) {
        case .success(let made): request = made
        case .failure(let error): return .error(error.message, exitCode: IPCExitCode.usage)
        }
        let output = RecipeRunOutput(context: nil, streamStdout: false, streamStderr: false)
        request.output = output
        let result = await recipes.start(request).result
        let ocr = result.variables["OcrText"] != nil
        let picture = await AIToolCatalog.picture(of: result.payload, maxImageSize: tool.maxImageSize, ocr: ocr,
                                                  language: app.settings.value.ocrLanguage)
        let collected = output.collected
        let reply = AIToolCatalog.runReply(result, tool: tool, stdout: collected.stdout, stderr: collected.stderr, picture: picture)
        if picture != nil {
            let title = result.payload?.title.isEmpty == false ? result.payload?.title ?? tool.title : tool.title
            center.notifyCapture(client: client.displayName, what: "'\(title)' (\(tool.title))")
        }
        return reply
    }

    /// PROPOSE_RECIPE: the approval sheet, saved only when the user approves it; "Open in the recipe editor after saving"
    /// opens the saved file here (the sheet doesn't).
    private static func proposeRecipe(_ app: AppDelegate, _ center: AIToolsCenter, _ context: IPCReplyContext) async -> IPCReply {
        let client: AIToolClient
        switch center.client(of: context) {
        case .success(let identified): client = identified
        case .failure: return .error(AIToolAccess.notAllowedMessage)
        }
        let recipes = app.recipes
        await recipes.whenLoaded()
        let envelope = context.envelope
        let proposal = AIRecipeProposals.Proposal(json: envelope.parameter("recipe"), request: envelope.parameter("request"),
                                                  explanation: envelope.parameter("explanation"), replaces: envelope.parameter("replaces"),
                                                  client: client)
        let outcome = await center.recipeProposals(recipes).propose(proposal)
        if let file = outcome.openInEditor { RecipeEditorService.openFile(file) }
        return outcome.reply
    }

    private static func recipeCommand(_ app: AppDelegate, _ body: @MainActor (RecipeLibrary) -> IPCReply) async -> IPCReply {
        let recipes = app.recipes
        await recipes.whenLoaded()
        return body(recipes.library)
    }
}

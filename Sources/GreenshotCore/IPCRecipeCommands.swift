// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The recipe commands of the command line and of links (upstream `IpcSecurityDispatcher.HandleListRecipesAsync`,
/// `HandleDescribeRecipeAsync`, `HandleRunRecipeAsync`; docs/recipe-contracts-cli-query-plan.md): LIST_RECIPES,
/// DESCRIBE_RECIPE, RUN_RECIPE. The app passes its library and how it starts a flow.
@MainActor
public enum IPCRecipeCommands {
    /// Starts a prepared request (the app's `RecipeRuntime.start`).
    public typealias Start = @MainActor (RecipeRunRequest) -> RecipeFlowHandle
    /// Asks the user before a recipe of the command line captures without them (`AutomationConsent`): true = allowed.
    public typealias ConfirmCapture = @MainActor (_ recipeName: String, _ subject: String) async -> Bool

    /// Text for a terminal (greenshot-cli without `--json`); JSON clients read the members.
    static func wantsText(_ context: IPCReplyContext) -> Bool {
        context.usesTextFrames && !context.envelope.json
    }

    // MARK: LIST_RECIPES

    /// The recipes with an active Commandline trigger, with their arguments.
    public static func listRecipes(_ context: IPCReplyContext, library: RecipeLibrary) -> IPCReply {
        let entries = library.commands(for: .commandLine).map { command -> JSONValue in
            let recipe = library.recipe(id: command.recipeId)?.recipe
            let entry: JSONObject = [
                "id": .string(command.recipeId),
                "name": .string(recipe?.name ?? command.recipeId),
                "command": .string(command.command),
                "description": .string(command.description ?? ""),
                "fire_and_forget": .bool(command.fireAndForget),
                "stdout": command.stdout.map(JSONValue.string) ?? .null,
                "arguments": .array(command.arguments.map(argumentJSON)),
            ]
            return .object(entry)
        }
        var extra: JSONObject = ["recipes": .array(entries)]
        if !library.isFeatureEnabled { extra["recipes_enabled"] = .bool(false) }
        return .ok(wantsText(context) ? IPCRecipeText.recipeList(entries) : nil, extra: extra)
    }

    /// A declared argument as LIST_RECIPES and DESCRIBE_RECIPE write it.
    static func argumentJSON(_ argument: CommandlineArgument) -> JSONValue {
        let object: JSONObject = [
            "name": .string(argument.name),
            "variable": .string(argument.effectiveVariable),
            "description": .string(argument.description ?? ""),
            "required": .bool(argument.required),
            "default_value": argument.defaultValue.map(JSONValue.string) ?? .null,
            "type": .string(argument.type.rawValue),
            "allowed_values": argument.allowedValues.map { .array($0.map(JSONValue.string)) } ?? .null,
        ]
        return .object(object)
    }

    // MARK: DESCRIBE_RECIPE

    /// The recipe by id, name or a trigger's Command (upstream's order), its triggers and its contract.
    public static func describeRecipe(_ context: IPCReplyContext, library: RecipeLibrary,
                                      contracts: StepContractCatalog = .builtIn) -> IPCReply {
        let target = (context.envelope.recipe ?? context.envelope.parameter("recipe") ?? context.envelope.rawInput ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return .error("Missing required argument: recipe name or ID to describe.") }
        let match = library.recipes.first { loaded in
            recipeEqualsAny(target, loaded.recipe.id, loaded.recipe.name)
                || loaded.recipe.triggers.contains { $0.command.map { recipeEqualsAny(target, $0) } ?? false }
        }
        guard let loaded = match, let report = library.contractReport(recipeId: loaded.recipe.id) else {
            return .error("Recipe '\(target)' not found.")
        }
        let recipe = loaded.recipe
        let triggers = recipe.triggers.map { trigger -> JSONValue in
            var object: JSONObject = ["type": .string(trigger.triggerType)]
            object["command"] = trigger.command.map(JSONValue.string) ?? .null
            object["description"] = trigger.commandDescription.map(JSONValue.string) ?? .null
            object["stdout"] = trigger.stdout.map(JSONValue.string) ?? .null
            let arguments = trigger.arguments
            object["arguments"] = arguments.isEmpty ? .null : .array(arguments.map(argumentJSON))
            return .object(object)
        }
        let inputs = report.inputs.map { input -> JSONValue in
            .object(["name": .string(input.name), "type": .string(input.dataType.rawValue), "required": .bool(input.required),
                     "description": .string(input.description), "default_value": input.exampleValue.map(JSONValue.string) ?? .null])
        }
        let outputs = report.outputs.map { output -> JSONValue in
            .object(["name": .string(output.name), "type": .string(output.dataType.rawValue),
                     "description": .string(output.description), "conditional": .bool(output.conditional)])
        }
        let steps = report.steps.map { step -> JSONValue in
            let requiresImage = contracts.contract(for: step.stepType)?.payload.rawCapture == .required
            return .object(["node_id": .string(step.nodeId), "step_type": .string(step.stepType),
                            "display_name": .string(step.displayName),
                            "required_inputs": .array(step.requiredInputs.map(JSONValue.string)),
                            "produced_outputs": .array(step.producedOutputs.map(JSONValue.string)),
                            "requires_image": .bool(requiresImage), "reachable": .bool(step.reachable)])
        }
        let lifecycle: JSONObject = ["acquires_image": .bool(report.acquiresImage), "mutates_pixels": .bool(report.mutatesPixels),
                                     "extracts_text": .bool(report.extractsText)]
        let contract: JSONObject = ["inputs": .array(inputs), "outputs": .array(outputs), "steps": .array(steps),
                                    "lifecycle": .object(lifecycle), "warnings": .array(report.warnings.map(JSONValue.string))]
        let info: JSONObject = ["id": .string(recipe.id), "name": .string(recipe.name), "description": .string(recipe.description ?? ""),
                                "category": .string("General"), "triggers": .array(triggers), "contract": .object(contract)]
        return .ok(wantsText(context) ? IPCRecipeText.recipeDescription(.object(info)) : nil, extra: ["recipe": .object(info)])
    }

    private static func recipeEqualsAny(_ target: String, _ names: String...) -> Bool {
        names.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
    }

    // MARK: RUN_RECIPE

    /// Upstream `IsBrowserSource`: a web page's link or the browser extension. Their recipes need `AllowBrowserInvocation`
    /// and its own approval.
    public static func isBrowserSource(_ source: IPCSource) -> Bool {
        source == .urlScheme || source == .nativeMessaging
    }

    /// Runs the recipe of a Commandline trigger: its arguments bound by their declared types, streamed Stdout/Stderr step
    /// output, `--json`, `--query`, `--async`. A recipe from greenshot-cli that captures without the user asks first.
    public static func runRecipe(_ context: IPCReplyContext, library: RecipeLibrary, start: Start,
                                 confirmCapture: ConfirmCapture) async -> IPCReply {
        let envelope = context.envelope
        let target = (envelope.recipe ?? envelope.parameter("recipe") ?? envelope.rawInput ?? "").trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return .error("Missing required argument: recipe command or recipe ID.") }
        guard library.isFeatureEnabled else {
            return .error("Recipes are switched off in Greenshot for Mac. Switch them on in Settings › Recipes.")
        }
        let browser = isBrowserSource(context.source)
        // Command, id, then name (upstream matches all three; the library knows command and id)
        let commandLine = library.commands(for: .commandLine)
        guard let match = commandLine.first(where: { recipeEqualsAny(target, $0.command) })
                ?? commandLine.first(where: { recipeEqualsAny(target, $0.recipeId) })
                ?? commandLine.first(where: { library.recipe(id: $0.recipeId).map { recipeEqualsAny(target, $0.recipe.name) } ?? false }),
              let loaded = library.recipe(id: match.recipeId) else {
            return .error("Recipe '\(target)' not found or does not have an active CommandlineTrigger.")
        }
        if browser, !loaded.isBrowserInvocationApproved(at: match.triggerIndex) {
            log.warn("[SECURITY] RUN_RECIPE rejected: recipe '\(match.recipeId)' does not allow invocation from source '\(context.source.rawValue)'.")
            return .error("[SECURITY] Recipe '\(target)' does not allow invocation from a browser. Set 'AllowBrowserInvocation' on its Commandline trigger to enable this.")
        }
        let query = envelope.query.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        // --query evaluates any expression (also environment and configuration values): command line only
        if query != nil, context.source != .cli {
            log.warn("[SECURITY] RUN_RECIPE rejected: --query is not allowed from source '\(context.source.rawValue)'.")
            return .error("[SECURITY] Queries are only allowed from the command line.")
        }
        // The arguments: the command line's key=value, or the query of a link; "recipe" is the target itself
        var supplied = envelope.parameters
        for key in supplied.keys where key.caseInsensitiveCompare("recipe") == .orderedSame { supplied.removeValue(forKey: key) }
        if let refusal = argumentRefusal(declared: match.arguments, supplied: supplied, aiTool: false) {
            return .error(refusal, exitCode: IPCExitCode.usage)
        }
        var request: RecipeRunRequest
        do {
            request = try library.runRequest(command: match.command, arguments: supplied, source: browser ? .browser : .commandLine) { raw, _ in
                switch IPCPathValidator.sanitize(raw, cwd: context.source == .cli ? envelope.cwd : nil) {
                case .success(let url): return url.path
                case .failure(let failure): throw RecipeStepError("[SECURITY] \(failure.message)")
                }
            }
        } catch {
            let message = (error as? RecipeStepError)?.message ?? error.localizedDescription
            log.warn("RUN_RECIPE '\(match.recipeId)' rejected: \(message)")
            let usage = (error as? RecipeStepError)?.errorType == "ArgumentException"
            return .error(message, exitCode: usage ? IPCExitCode.usage : IPCExitCode.failure)
        }
        // Mac only: greenshot-cli can be run by any program; a capture without the user on the capture screen asks first
        let prepared = RecipeTriggerPreparer.prepare(loaded.recipe, triggerType: WellKnownTriggerType.commandline)
        if let subject = AutomationConsent.recipeCaptureSubject(prepared, variables: request.variables, source: context.source),
           await !confirmCapture(loaded.recipe.name, subject) {
            return .error("The recipe '\(loaded.recipe.name)' wasn't run: its screenshot wasn't allowed.")
        }

        let fireAndForget = envelope.async || match.fireAndForget
        if fireAndForget {
            // The reply goes out now and the client disconnects: nothing of the flow is bound to the connection
            _ = start(request)
            return .ok("Recipe '\(loaded.recipe.name)' triggered in background.", extra: ["recipe": .string(loaded.recipe.id)])
        }

        let json = envelope.json
        // Plain runs stream Stdout/Stderr step output at once; --query prints only its value and --json collects
        // everything into the one result document.
        let output = RecipeRunOutput(context: context, streamStdout: query == nil && !json, streamStderr: !json)
        request.output = output
        let stdoutExpression = match.stdout.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let evaluated = EvaluatedOutput()
        request.onFinish = { flow in
            let scope = flow.scope()
            if let query { evaluated.set(query: flow.evaluator.evaluate(query, in: scope).interpolationText) }
            if let stdoutExpression { evaluated.set(stdout: flow.evaluator.evaluate(stdoutExpression, in: scope).interpolationText) }
        }
        let result = await start(request).result
        return runReply(result, recipe: loaded.recipe, json: json, query: query != nil, stdoutExpression: stdoutExpression != nil,
                        output: output, evaluated: evaluated)
    }

    /// Declared Window arguments only for AI tools; Region arguments must be "x,y,width,height" (upstream
    /// `CommandlineArgumentBinder.TryConvert`).
    static func argumentRefusal(declared: [CommandlineArgument], supplied: [String: String], aiTool: Bool) -> String? {
        for argument in declared {
            guard let value = supplied.first(where: { $0.key.caseInsensitiveCompare(argument.name) == .orderedSame })?.value,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if argument.type == .window, !aiTool {
                return "Error: argument '--\(argument.name)' is a window, window arguments are only available to AI tools."
            }
            if argument.type == .region, AIToolRegion(text: value) == nil {
                return "Error: argument '--\(argument.name)' expects a region 'x,y,width,height' in screen coordinates (width and height above 0), got '\(value)'."
            }
        }
        return nil
    }

    /// The final reply of a run that was waited for (upstream's output priorities).
    static func runReply(_ result: RecipeFlowResult, recipe: CaptureRecipe, json: Bool, query: Bool, stdoutExpression: Bool,
                         output: RecipeRunOutput, evaluated: EvaluatedOutput) -> IPCReply {
        let failed = result.state == .failed || result.state == .cancelled
        // A Stderr step's exit code also when it didn't abort
        let exitCode = result.exitCode != 0 ? Int32(clamping: result.exitCode) : (failed ? IPCExitCode.failure : IPCExitCode.ok)
        var stdout: String?
        var stderr: String?
        let collected = output.collected
        if failed {
            let reason = result.reason ?? result.errorDescription ?? "Recipe execution failed or was aborted."
            // A Stderr step streamed its message already; the abort reason would print it twice
            if !collected.streamedStderr { stderr = collected.stderr.isEmpty ? reason : collected.stderr.joined(separator: "\n") }
            if json, !collected.stdout.isEmpty { stdout = collected.stdout.joined(separator: "\n") }
        } else {
            if query {
                // 1. --query replaces the recipe's own output
                stdout = evaluated.query ?? ""
            } else if collected.streamedStdout {
                // 2. Stdout steps streamed it already
                stdout = nil
            } else if !collected.stdout.isEmpty {
                // 3. --json collected the Stdout steps' output
                stdout = collected.stdout.joined(separator: "\n")
            } else if stdoutExpression {
                // 4. The trigger's Stdout expression
                stdout = evaluated.stdout ?? ""
            } else {
                // 5. What the recipe produced
                stdout = fallbackOutput(result, recipe: recipe)
            }
            if !collected.streamedStderr, !collected.stderr.isEmpty { stderr = collected.stderr.joined(separator: "\n") }
        }
        let status = failed ? "error" : "ok"
        guard json else { return IPCReply(status: status, exitCode: exitCode, stdout: stdout, stderr: stderr) }
        var variables = JSONObject()
        for member in result.variables { variables[member.key] = member.value }
        let extra: JSONObject = ["recipe": .string(recipe.id), "payload": payloadSummary(result.payload),
                                 "variables": .object(variables)]
        return IPCReply(status: status, exitCode: exitCode, stdout: stdout, stderr: stderr, extra: extra)
    }

    /// Upstream `GetFallbackOutputAsync`: the output of a recipe without a Stdout step, Stdout expression or query.
    static func fallbackOutput(_ result: RecipeFlowResult, recipe: CaptureRecipe) -> String {
        for name in ["CommandResult", "OutputText", "LastStdout", "Text", "OcrText", "Barcode.Text", "Zxing.DecodedText"] {
            if let value = result.variables[name], !value.isNull {
                let text = value.interpolationText
                if !text.isEmpty { return text }
            }
        }
        if let text = result.payload?.extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        if let file = result.variables["Destination.Filename"], !file.isNull, !file.interpolationText.isEmpty {
            return file.interpolationText
        }
        return "Recipe '\(recipe.name)' completed successfully."
    }

    /// Upstream `CreatePayloadSummary`.
    static func payloadSummary(_ payload: RecipePayload?) -> JSONValue {
        guard let payload else { return .null }
        let image = payload.image
        let summary: JSONObject = [
            "width": .number(Double(image.width)),
            "height": .number(Double(image.height)),
            "format": .string("\(image.bitsPerPixel)bpp"),
            "extracted_text": payload.extractedText.map(JSONValue.string) ?? .null,
            "metadata": .object(JSONObject(payload.metadata.keys.sorted().map { JSONMember($0, payload.metadata[$0] ?? .null) })),
        ]
        return .object(summary)
    }
}

/// What a run wrote with Stdout and Stderr steps: streamed to the caller as it comes (plain runs) and collected for the
/// final reply (upstream's StdoutWriter / StderrWriter of `HandleRunRecipeAsync`).
final class RecipeRunOutput: RecipeOutputSink, @unchecked Sendable {
    struct Collected {
        var stdout: [String] = []
        var stderr: [String] = []
        var streamedStdout = false
        var streamedStderr = false
    }

    private let context: IPCReplyContext?
    private let streamStdout: Bool
    private let streamStderr: Bool
    private let lock = NSLock()
    private var state = Collected()

    init(context: IPCReplyContext?, streamStdout: Bool, streamStderr: Bool) {
        self.context = context
        self.streamStdout = streamStdout
        self.streamStderr = streamStderr
    }

    var collected: Collected { lock.withLock { state } }

    func writeStdout(_ text: String) async {
        lock.withLock {
            state.stdout.append(text)
            if streamStdout { state.streamedStdout = true }
        }
        if streamStdout { context?.stream(text, to: .stdout) }
    }

    func writeStderr(_ text: String) async {
        lock.withLock {
            state.stderr.append(text)
            if streamStderr { state.streamedStderr = true }
        }
        if streamStderr { context?.stream(text, to: .stderr) }
    }
}

/// The query's and the trigger's Stdout values, evaluated while the flow's variables are there (`onFinish`).
final class EvaluatedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var queryValue: String?
    private var stdoutValue: String?

    var query: String? { lock.withLock { queryValue } }
    var stdout: String? { lock.withLock { stdoutValue } }

    func set(query: String) { lock.withLock { queryValue = query } }
    func set(stdout: String) { lock.withLock { stdoutValue = stdout } }
}

private let log = Log("IPC")

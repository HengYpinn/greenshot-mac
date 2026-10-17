// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A recipe an AI tool sent, read and checked (upstream `AiRecipeIpcHandler.ParsedProposal`).
public struct AIRecipeDraft: Sendable {
    public var recipe: CaptureRecipe
    public var validation: RecipeValidationResult
    /// The recipe as Greenshot writes it: this is shown, hashed and saved, not the AI tool's formatting.
    public var content: String

    public var isExtension: Bool { recipe.kind == .extension }
}

/// RECIPE_CATALOG and VALIDATE_RECIPE (upstream `Ai/AiRecipeIpcHandler.cs`): what recipes can use in this Greenshot, and
/// checking a recipe an AI tool wrote. Nothing is saved or shown.
@MainActor
public enum AIRecipeCatalog {
    /// Keys a file may carry that only Greenshot decides (upstream resets FilePath, IsBuiltIn, IsOverridden, ProposedBy).
    static let originKeys = ["isBuiltIn", "filePath", "isOverridden", "isEnabled", "proposedBy"]

    /// Reads and checks the JSON of exactly one recipe or automatic step; nil error = ok.
    public static func parse(_ json: String?, library: RecipeLibrary) -> Result<AIRecipeDraft, AIToolError> {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(AIToolError("The recipe JSON is missing."))
        }
        guard json.utf8.count <= RecipeFileReader.maxBytes else {
            return .failure(AIToolError("The recipe is too large (more than \(RecipeFileReader.maxBytes / 1024 / 1024) MB)."))
        }
        let recipes: [CaptureRecipe]
        do {
            recipes = try RecipeSerializer.decode(text: json)
        } catch {
            let message = (error as? RecipeFormatError)?.message ?? error.localizedDescription
            return .failure(AIToolError("The recipe is not valid JSON for a recipe: \(message)"))
        }
        guard recipes.count == 1, var recipe = recipes.first, json.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            return .failure(AIToolError("Send exactly one recipe (a JSON object, not a list)."))
        }
        // Where it comes from is decided by Greenshot, not by the JSON
        for key in originKeys { recipe.extra.removeValue(forKey: key) }
        let validation = RecipeValidator(contracts: library.contracts, gates: library.gates()).validate(recipe)
        return .success(AIRecipeDraft(recipe: recipe, validation: validation, content: RecipeSerializer.encode(recipe)))
    }

    /// Why an AI tool may not propose this automatic step: it needs a Boolean option "enabled", its switch in
    /// Settings › Recipes, so it can start switched off (security review SM-M3); nil for a recipe or a fine step.
    /// TODO(merge): the same check is RMANAGER's `RecipeExtensionNames.aiProposalProblem(_:)` on wave4/integration; use it
    /// there and drop this copy.
    public static func aiProposalProblem(_ recipe: CaptureRecipe) -> String? {
        guard recipe.kind == .extension else { return nil }
        if let option = recipe.option("enabled"), option.type == .boolean { return nil }
        return "An automatic step from an AI tool needs a Boolean option \"enabled\" (its switch in Settings › Recipes), e.g. \"options\": [{ \"key\": \"enabled\", \"type\": \"Boolean\", \"default\": false }], and its nodes should use it (\"enabled\": \"${option.enabled}\")."
    }

    // MARK: RECIPE_CATALOG

    /// The catalog, or with `recipeId` the JSON of that recipe or automatic step (to change it with update_recipe).
    public static func catalogReply(recipeId: String?, library: RecipeLibrary) -> IPCReply {
        let wanted = recipeId?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !wanted.isEmpty else { return .ok(nil, extra: catalog(library: library)) }
        if let loaded = library.recipe(id: wanted) {
            var copy = loaded.recipe
            for key in originKeys { copy.extra.removeValue(forKey: key) }
            return .ok(nil, extra: ["recipe": .string(loaded.recipe.id), "kind": .string(RecipeKind.recipe.rawValue),
                                    "built_in": .bool(loaded.isBuiltIn), "replaces_built_in": .bool(loaded.replacesBuiltIn),
                                    "recipe_json": .string(RecipeSerializer.encode(copy))])
        }
        if let loaded = library.extensions.first(where: { recipeEquals($0.recipe.id, wanted) }) {
            return .ok(nil, extra: ["recipe": .string(loaded.recipe.id), "kind": .string(RecipeKind.extension.rawValue),
                                    "built_in": .bool(loaded.isBuiltIn), "replaces_built_in": .bool(loaded.replacesBuiltIn),
                                    "recipe_json": .string(RecipeSerializer.encode(loaded.recipe))])
        }
        return .error("There is no recipe or automatic step with the id '\(wanted)'.")
    }

    static let notes = [
        "Write a recipe as JSON following the recipe schema (get_recipe_schema), using only the step types, destinations and processors listed here.",
        "Check it with validate_recipe, then propose_recipe shows it to the user. Nothing is saved or run unless the user approves it.",
        "A new recipe needs an id that no recipe uses; to change a recipe (also a built-in one) use update_recipe with its id.",
        "The user switches each trigger on or off; for a recipe from an AI tool they start switched off. Uploads, files outside the output folder and external commands need the user's permission.",
        "Destinations with uploads=true send the capture to the internet.",
        "Greenshot for Mac runs on macOS: hotkeys are written like \"Ctrl + Shift + B\", where Ctrl means ⌘ (Command) and Win means ⌃ (Control); screen coordinates are points with the origin at the top left of the main display.",
        "An automatic step (\"kind\": \"extension\") adds steps to other recipes, e.g. a border on every capture: \"extends\": { \"recipes\": [ ids, \"*\" or \"*capture\" ], \"slot\": one of the slots, \"order\" }, an optional \"when\" expression, no triggers and no Source step. Its flow starts at its startNodes; a transition to \"Out\" ends it and the recipe goes on. Destinations only at AfterExport. Propose and update it like a recipe; it starts switched off, the user switches it on in Settings › Recipes.",
        "Options (\"options\") are values the user sets once in Settings › Recipes, read by the steps with ${option.key}. Give an automatic step a Boolean option \"enabled\" as its on/off switch. A String option can't be used by a step which needs a permission; \"format\": \"template\" lets its value contain ${...}.",
    ]

    static let triggerTypes: [JSONValue] = [
        trigger(WellKnownTriggerType.hotkey, "Hotkey (e.g. \"Ctrl + Shift + F9\"; Ctrl is ⌘ on the Mac)", "starts when the user presses the hotkey"),
        trigger(WellKnownTriggerType.contextMenu, "MenuItemText, Group, Order", "an entry in the Greenshot menu"),
        trigger(WellKnownTriggerType.editor, "MenuItemText, Group, Order", "an entry in the editor's recipe menu, works on the open image"),
        trigger(WellKnownTriggerType.clipboard, "OnImageCopied, FormatFilter", "runs on its own when an image is copied"),
        trigger(WellKnownTriggerType.manual, "", "only started from the recipe list"),
        trigger(WellKnownTriggerType.commandline, "Command, Description, FireAndForget, Stdout, Arguments, AllowBrowserInvocation",
                "greenshot-cli --recipe <Command>"),
        trigger(WellKnownTriggerType.openFile, "Filter, FireAndForget", "runs for files opened with Greenshot"),
        trigger(WellKnownTriggerType.extension, "Browser, FireAndForget", "handles captures from the browser extension"),
        trigger(WellKnownTriggerType.aiTool, "ToolName, Title, Description, ReadOnly, Destructive, Arguments, MaxImageSize",
                "offers the recipe as a tool to AI tools"),
    ]

    private static func trigger(_ type: String, _ parameters: String, _ note: String) -> JSONValue {
        .object(["type": .string(type), "parameters": .string(parameters), "note": .string(note)])
    }

    static let slots: [(name: String, where: String)] = [
        ("AfterCapture", "after the capture and the selection, before the processors"),
        ("BeforeExport", "once before the destinations, the image is final"),
        ("AfterExport", "after the destinations"),
        ("BeforeDestination", "for each destination on its own copy of the capture (the user can limit it to some destinations)"),
    ]

    static func catalog(library: RecipeLibrary) -> JSONObject {
        let gates = library.gates()
        let steps = library.contracts.all.filter { !$0.stepType.isEmpty }
            .sorted { $0.stepType.lowercased() < $1.stepType.lowercased() }
            .map(describe)
        let destinations = CaptureDestination.allCases.map { destination -> JSONValue in
            let designation = RecipeDestinationDesignation.designation(for: destination)
            let uploads = RecipeDestinationDesignation(designation).gatedAction(gates)?.gateType == .networkAccess
            return .object(["designation": .string(designation), "name": .string(destination.displayName), "uploads": .bool(uploads)])
        }.sorted { ($0.objectValue?.string("designation") ?? "").lowercased() < ($1.objectValue?.string("designation") ?? "").lowercased() }
        let processors: [JSONValue] = [
            .object(["id": .string("Windows10OcrProcessor"), "designation": .string("OCR"),
                     "description": .string("Text recognition with macOS Vision: sets OcrText, Text and the extracted text")]),
        ]
        let recipes = library.recipes.map { loaded -> JSONValue in
            .object(["id": .string(loaded.recipe.id), "name": .string(loaded.recipe.name),
                     "description": loaded.recipe.description.map(JSONValue.string) ?? .null,
                     "built_in": .bool(loaded.isBuiltIn), "replaces_built_in": .bool(loaded.replacesBuiltIn),
                     "enabled": .bool(loaded.isEnabled), "ai_created": .bool(loaded.proposedBy != nil),
                     "triggers": .array(loaded.recipe.triggers.map { .string($0.triggerType) })])
        }
        let slotList = slots.map { slot -> JSONValue in
            let users = library.recipes.filter { loaded in
                loaded.recipe.nodes.contains { recipeEquals($0.stepType, WellKnownStepType.slot) && recipeEquals($0.parameters.string("Name") ?? "", slot.name) }
            }.map { JSONValue.string($0.recipe.id) }
            return .object(["name": .string(slot.name), "where": .string(slot.where), "recipes": .array(users)])
        }
        let automaticSteps = library.extensions.map { loaded -> JSONValue in
            let extends = loaded.recipe.extends
            return .object(["id": .string(loaded.recipe.id), "name": .string(loaded.recipe.name),
                            "description": loaded.recipe.description.map(JSONValue.string) ?? .null,
                            "slot": extends?.slot.map(JSONValue.string) ?? .null,
                            "recipes": .array((extends?.recipes ?? []).map(JSONValue.string)),
                            "order": .number(Double(extends?.order ?? 0)), "built_in": .bool(loaded.isBuiltIn),
                            "switched_on": .bool(loaded.isEnabled), "ai_created": .bool(loaded.proposedBy != nil)])
        }
        let optionTypes: [ContractDataType] = [.boolean, .integer, .decimal, .string, .enumeration, .color]
        return [
            "notes": .array(notes.map(JSONValue.string)),
            "trigger_types": .array(triggerTypes),
            "steps": .array(steps),
            "destinations": .array(destinations),
            "processors": .array(processors),
            "recipes": .array(recipes),
            "slots": .array(slotList),
            "option_types": .array(optionTypes.map { .string($0.rawValue) }),
            "automatic_steps": .array(automaticSteps),
        ]
    }

    private static func describe(_ contract: StepContract) -> JSONValue {
        let parameters = contract.parameters.map { parameter -> JSONValue in
            let allowed = parameter.allowedValues.isEmpty ? (parameter.allowedValuesProvider?() ?? []) : parameter.allowedValues
            return .object(["name": .string(parameter.name), "type": .string(parameter.dataType.rawValue), "required": .bool(parameter.required),
                            "default_value": parameter.defaultValue.map { .string($0.interpolationText) } ?? .null,
                            "allowed_values": .array(allowed.map(JSONValue.string)),
                            "supports_expressions": .bool(parameter.supportsExpressions), "description": .string(parameter.description)])
        }
        let inputs = contract.inputVariables.map { variable -> JSONValue in
            .object(["name": .string(variable.name), "type": .string(variable.dataType.rawValue), "required": .bool(variable.required),
                     "description": .string(variable.description)])
        }
        let outputs = contract.outputVariables.map { variable -> JSONValue in
            .object(["name": .string(variable.name), "type": .string(variable.dataType.rawValue), "conditional": .bool(variable.conditional),
                     "description": .string(variable.description)])
        }
        let payload: JSONObject = ["raw_capture": .string(contract.payload.rawCapture.rawValue),
                                   "surface": .string(contract.payload.surface.rawValue),
                                   "extracted_text": .string(contract.payload.extractedText.rawValue),
                                   "visual_mutation": .string(contract.payload.visualMutation.rawValue)]
        return .object(["step_type": .string(contract.stepType), "name": .string(contract.displayName),
                        "description": .string(contract.description), "category": .string(contract.category),
                        "accepts_other_parameters": .bool(contract.acceptsUndeclaredParameters),
                        "parameters": .array(parameters), "inputs": .array(inputs), "outputs": .array(outputs), "payload": .object(payload)])
    }

    // MARK: VALIDATE_RECIPE

    /// Errors, warnings, what it does and what the user will be asked to allow; nothing is saved or shown.
    public static func validateReply(json: String?, library: RecipeLibrary) -> IPCReply {
        let draft: AIRecipeDraft
        switch parse(json, library: library) {
        case .success(let parsed): draft = parsed
        case .failure(let error): return .error(error.message)
        }
        var validation = draft.validation
        if let problem = aiProposalProblem(draft.recipe) { validation.errors.append(problem) }
        let describer = RecipeDescriber(contracts: library.contracts, gates: library.gates())
        let permissions = validation.gatedActions.map { action -> JSONValue in
            .object(["kind": .string(action.gateType.rawValue), "what": .string(describer.describe(action))])
        }
        let steps = validation.isValid ? describer.describeSteps(draft.recipe).map { JSONValue.string($0.text) } : []
        let triggers = describer.describeTriggers(draft.recipe).map { JSONValue.string($0.label) }
        let reach = draft.isExtension && validation.isValid ? library.describeExtensionReach(draft.recipe).map(JSONValue.string) : []
        let id = draft.recipe.id
        let existing = library.recipe(id: id) != nil || library.extensions.contains { recipeEquals($0.recipe.id, id) }
        let summary = validation.isValid ? "The recipe is valid." : "The recipe has \(validation.errors.count) error(s)."
        return .ok(summary, extra: [
            "valid": .bool(validation.isValid),
            "errors": .array(validation.errors.map(JSONValue.string)),
            "warnings": .array(validation.warnings.map(JSONValue.string)),
            "needs_permission": .array(permissions),
            "what_it_does": .array(steps),
            "triggers": .array(triggers),
            "kind": .string(draft.recipe.kind.rawValue),
            "changes_other_recipes": .array(reach),
            "existing_recipe": .bool(existing),
        ])
    }
}

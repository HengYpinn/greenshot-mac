// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where a loaded recipe comes from.
public enum RecipeSource: Sendable, Equatable {
    case builtIn
    case file(URL)
}

/// A recipe Greenshot knows (upstream `CaptureRecipe` with its runtime state): file content plus where it came from,
/// whether it is switched on, its approval.
public struct LoadedRecipe: Sendable {
    public var recipe: CaptureRecipe
    public var source: RecipeSource
    /// Not in `RecipeSettings.disabledRecipeIds`.
    public var isEnabled: Bool
    /// A file replaces the built-in recipe with the same id.
    public var replacesBuiltIn: Bool
    /// Nil for built-in recipes (always approved).
    public var approval: RecipeApproval?
    /// The AI tool that wrote the file.
    public var proposedBy: String?
    public var validation: RecipeValidationResult

    public init(recipe: CaptureRecipe, source: RecipeSource, isEnabled: Bool = true, replacesBuiltIn: Bool = false,
                approval: RecipeApproval? = nil, proposedBy: String? = nil, validation: RecipeValidationResult = RecipeValidationResult()) {
        self.recipe = recipe
        self.source = source
        self.isEnabled = isEnabled
        self.replacesBuiltIn = replacesBuiltIn
        self.approval = approval
        self.proposedBy = proposedBy
        self.validation = validation
    }

    public var isBuiltIn: Bool { source == .builtIn }
    /// Enabled in the recipe and approved (built-in: enabled), when the recipe is switched on (upstream `IsActive`).
    public func isTriggerActive(at index: Int) -> Bool { rcoreStub() }
    /// A Commandline trigger's browser invocation is approved too.
    public func isBrowserInvocationApproved(at index: Int) -> Bool { rcoreStub() }
}

/// A trigger that may start its recipe now, for a trigger source (upstream `SyncRecipeTriggers`).
public struct ActiveRecipeTrigger: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var index: Int
    public var trigger: TriggerConfig
    /// The parsed hotkey of a Hotkey trigger.
    public var hotkey: KeyCombo?
    public var browserInvocationApproved: Bool

    public init(recipeId: String, recipeName: String, index: Int, trigger: TriggerConfig, hotkey: KeyCombo? = nil,
                browserInvocationApproved: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.index = index
        self.trigger = trigger
        self.hotkey = hotkey
        self.browserInvocationApproved = browserInvocationApproved
    }

    public var key: String { RecipeApprovalPolicy.triggerKey(index: index, trigger: trigger) }
}

/// A recipe that can run as a command (Commandline trigger; upstream `--list-recipes`).
public struct RecipeCommand: Sendable, Equatable {
    public var recipeId: String
    /// The command name (the trigger's `Command`, else the recipe id).
    public var command: String
    public var description: String?
    public var arguments: [CommandlineArgument]
    public var fireAndForget: Bool
    /// The trigger's `Stdout` expression.
    public var stdout: String?
    public var triggerIndex: Int
    public var allowsBrowserInvocation: Bool

    public init(recipeId: String, command: String, description: String? = nil, arguments: [CommandlineArgument] = [],
                fireAndForget: Bool = false, stdout: String? = nil, triggerIndex: Int, allowsBrowserInvocation: Bool = false) {
        self.recipeId = recipeId
        self.command = command
        self.description = description
        self.arguments = arguments
        self.fireAndForget = fireAndForget
        self.stdout = stdout
        self.triggerIndex = triggerIndex
        self.allowsBrowserInvocation = allowsBrowserInvocation
    }
}

/// Who asks to run a command; browser callers need the `:browser` approval.
public enum RecipeInvocationSource: Sendable, Equatable {
    case commandLine
    case urlScheme
    case browser
    case aiTool(client: String)
}

/// The outcome of loading files (upstream `RecipeValidationResult` of `LoadRecipeFromFile`).
public struct RecipeLoadResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    public var loadedRecipeIds: [String] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
}

/// The recipes Greenshot knows and their approvals (upstream `RecipeManager`): built-in recipes, files listed in
/// `RecipeSettings.files` (no folder scanning), default-deny approval of each recipe of a file pinned to the SHA-256 of
/// its bytes, override and reset of built-ins, switching recipes on and off, saving from the editor with the edit
/// decision table, revoke and review, details, commands for the CLI. Nothing here draws: questions go to the approver.
@MainActor
public final class RecipeLibrary {
    /// - Parameters:
    ///   - loadSettings / saveSettings: `AppSettings.recipes` (the app's settings store).
    ///   - gates: the settings' external commands and destinations, for the gate check.
    ///   - watchFiles: watch the loaded files (`RecipeFileMonitor`) and ask again right after one changes; off in tests.
    public init(loadSettings: @escaping @MainActor () -> RecipeSettings,
                saveSettings: @escaping @MainActor (RecipeSettings) -> Void,
                trustStore: any RecipeTrustStoring,
                approver: (any RecipeApprover)?,
                builtInRecipes: [CaptureRecipe] = [],
                contracts: StepContractCatalog = .builtIn,
                gates: @escaping @MainActor () -> GateEnvironment = { .empty },
                watchFiles: Bool = true) { rcoreStub() }

    /// Called after recipes, approvals or the switch changed (resync triggers and menus).
    public var onChange: (@MainActor () -> Void)?

    /// Off: no recipe files are loaded, no recipe triggers (upstream `EnableRecipeFeature`).
    public var isFeatureEnabled: Bool { rcoreStub() }
    public var recipes: [LoadedRecipe] { rcoreStub() }
    public func recipe(id: String) -> LoadedRecipe? { rcoreStub() }
    public func builtInRecipe(id: String) -> CaptureRecipe? { rcoreStub() }
    /// The triggers that may start their recipes now, of the given types (all when nil).
    public func activeTriggers(ofTypes types: Set<String>? = nil) -> [ActiveRecipeTrigger] { rcoreStub() }

    /// The user's option values (RCP-006), for Settings > Recipes and the runs.
    public var optionValues: RecipeOptionValues { rcoreStub() }
    public func setOptionValue(_ value: JSONValue, key: String, recipeId: String) { rcoreStub() }
    public func resetOptions(recipeId: String) { rcoreStub() }

    /// Loads the files of the settings again (tray "Reload Recipes").
    public func reload() async -> RecipeLoadResult { rcoreStub() }
    /// Reads the file once, hashes the bytes, validates each recipe and asks for the approval of those not approved for
    /// this content (`interactive`); approved and allowed ones replace what was loaded and the file joins the settings.
    public func loadFile(_ url: URL, interactive: Bool = true, forcePrompt: Bool = false) async -> RecipeLoadResult { rcoreStub() }
    /// Import: load interactively.
    public func importFile(_ url: URL) async -> RecipeLoadResult { await loadFile(url) }
    /// The file monitor saw a change: asks right away when a recipe in use lost its approval (upstream `CheckChangedFile`).
    public func fileDidChange(_ url: URL) async { rcoreStub() }
    /// Before a run: the recipe as it may run (its file still approved, or approved again), nil when not
    /// (upstream `EnsureRecipeApprovedAndUpToDateAsync`). The runner's `preflight`.
    public func ensureApprovedAndCurrent(_ recipe: CaptureRecipe) async -> CaptureRecipe? { rcoreStub() }

    /// Saves from the recipe editor: the approval is renewed without asking unless `saveDecisionReasons` is not empty.
    public func save(_ recipe: CaptureRecipe, to url: URL) async -> RecipeLoadResult { rcoreStub() }
    public func saveDecisionReasons(for recipe: CaptureRecipe, at url: URL?) -> [String] { rcoreStub() }
    /// An AI tool's proposal (RCP-204): written to `url` after the user approved it, triggers and permissions off.
    public func propose(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?, saveTo url: URL) async -> RecipeLoadResult { rcoreStub() }

    public func setEnabled(_ enabled: Bool, recipeId: String) { rcoreStub() }
    /// Drops the file recipe and brings the built-in back ("Reset Default").
    @discardableResult
    public func resetToDefault(recipeId: String) -> Bool { rcoreStub() }
    public func resetAllToDefault() { rcoreStub() }
    /// Forgets a file recipe (manager "Unload"): out of the settings, approval kept.
    public func unload(recipeId: String) { rcoreStub() }
    @discardableResult
    public func revokeApproval(recipeId: String) -> Bool { rcoreStub() }
    /// "Permissions": the approval sheet in review mode.
    public func reviewApproval(recipeId: String) async -> RecipeLoadResult { rcoreStub() }
    public func details(recipeId: String) -> RecipeDetails? { rcoreStub() }
    /// The approval sheet read-only (Details).
    public func detailsRequest(recipeId: String) -> RecipeApprovalRequest? { rcoreStub() }

    /// The recipes with an active Commandline (or, for `.aiTool`, AiTool) trigger the source may start.
    public func commands(for source: RecipeInvocationSource) -> [RecipeCommand] { rcoreStub() }
    /// A run request for a command with bound arguments (`RecipeArgumentBinder`) and a Commandline (or AiTool) trigger
    /// info; the runner prepares the recipe for it. Throws `RecipeStepError` with a message for stderr (unknown command,
    /// not approved, bad arguments).
    public func runRequest(command: String, arguments: [String: String], source: RecipeInvocationSource,
                           resolvePath: (String, ContractDataType) throws -> String) throws -> RecipeRunRequest { rcoreStub() }
    /// A run request for a recipe by id (menu entry, test run) with a trigger info of this type; the runner prepares
    /// the recipe for it.
    public func runRequest(recipeId: String, triggerType: String = WellKnownTriggerType.manual) -> RecipeRunRequest? { rcoreStub() }
    /// The contract report of a recipe (`--info`).
    public func contractReport(recipeId: String) -> RecipeContractReport? { rcoreStub() }
}

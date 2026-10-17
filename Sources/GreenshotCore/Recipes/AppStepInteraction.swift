// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

// MARK: UserPrompt

/// One button of the UserPrompt step (upstream `PromptChoice`).
public struct RecipePromptChoice: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable {
        case primary = "Primary"
        case secondary = "Secondary"
        case danger = "Danger"
    }

    public var key: String
    public var label: String
    public var style: Style
    public var isDefault: Bool
    public var isCancel: Bool

    public init(key: String, label: String? = nil, style: Style = .primary, isDefault: Bool = false, isCancel: Bool = false) {
        self.key = key
        self.label = label ?? key
        self.style = style
        self.isDefault = isDefault
        self.isCancel = isCancel
    }
}

/// What the UserPrompt step shows and how its answer is decided (upstream `UserPromptStep` + `RecipeUserPromptWindow`).
public struct RecipePrompt: Equatable, Sendable {
    public var title: String
    public var message: String
    public var choices: [RecipePromptChoice]
    public var showPreview: Bool
    public var timeoutSeconds: Int
    /// The choice of Enter and of the countdown: `DefaultChoice`, else the first choice marked default, else the first.
    public var defaultKey: String
    /// The choice of Esc and of closing the window: the first marked cancel, else "No", else the last, else "No".
    public var cancelKey: String

    public init(_ step: RecipeStepInvocation) {
        title = Self.text(step.string("Title")) ?? "Decision Required"
        message = Self.text(step.string("Message")) ?? "Please select how you would like to proceed with this capture:"
        showPreview = step.bool("ShowPreview") ?? true
        timeoutSeconds = max(step.int("TimeoutSeconds") ?? 0, 0)
        var choices = Self.choices(step.value("Choices"))
        var defaultKey = choices.first(where: \.isDefault)?.key
        var cancelKey = choices.first(where: \.isCancel)?.key
        if choices.isEmpty {
            choices = [RecipePromptChoice(key: "Yes", label: "Yes, Proceed", style: .primary, isDefault: true),
                       RecipePromptChoice(key: "No", label: "No, Cancel", style: .secondary, isCancel: true)]
            defaultKey = "Yes"
            cancelKey = "No"
        }
        if cancelKey == nil {
            cancelKey = choices.first { recipeEquals($0.key, "No") }?.key ?? choices.last?.key
        }
        if let given = Self.text(step.string("DefaultChoice")) { defaultKey = given }
        self.choices = choices
        self.defaultKey = defaultKey ?? choices[0].key
        self.cancelKey = cancelKey ?? "No"
    }

    /// Upstream `ParseChoices`: objects with Key (required), Label, Style (default Primary), IsDefault, IsCancel.
    public static func choices(_ value: JSONValue?) -> [RecipePromptChoice] {
        (value?.arrayValue ?? []).compactMap { item in
            guard let object = item.objectValue, let key = text(object.string("Key")) else { return nil }
            let style = RecipePromptChoice.Style.allCases.first { recipeEquals($0.rawValue, object.string("Style") ?? "") } ?? .secondary
            let named = text(object.string("Style")) == nil ? RecipePromptChoice.Style.primary : style
            return RecipePromptChoice(key: key, label: text(object.string("Label")), style: named,
                                      isDefault: object.bool("IsDefault") ?? false, isCancel: object.bool("IsCancel") ?? false)
        }
    }

    /// How the prompt ended.
    public enum Answer: Equatable, Sendable {
        case chosen(String)
        case enter
        case escape
        case timedOut
        /// The window's close button.
        case closed
    }

    /// The key that goes into `UserChoice.<node id>`.
    public func key(for answer: Answer) -> String {
        switch answer {
        case .chosen(let key): return key
        case .enter, .timedOut: return defaultKey
        case .escape, .closed: return cancelKey
        }
    }

    /// "Auto-selecting default choice in 5s..." while the countdown runs.
    public static func countdownText(_ seconds: Int) -> String {
        seconds > 0 ? "Auto-selecting default choice in \(seconds)s..." : ""
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension RecipePromptChoice.Style: CaseIterable {}

/// The app's prompt window.
public protocol RecipePromptPresenting: Sendable {
    /// Shows the prompt (with `preview` when wanted) and waits for the answer; cancelling the task closes it.
    func ask(_ prompt: RecipePrompt, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipePrompt.Answer
}

/// Upstream `UserPromptStep`: asks, then `UserChoice.<node id>` holds the chosen key (the engine follows the conditional
/// transition with that key).
public struct RecipeUserPromptExecutor: RecipeStepExecutor {
    let presenter: any RecipePromptPresenting

    public init(presenter: any RecipePromptPresenting) {
        self.presenter = presenter
    }

    public func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let prompt = RecipePrompt(step)
        let preview = prompt.showPreview ? context.payload?.flattened() : nil
        let answer = try await presenter.ask(prompt, preview: preview, in: context)
        try Task.checkCancellation()
        let key = prompt.key(for: answer)
        context[variable: "UserChoice.\(step.node.id)"] = .string(key)
        context.log("User Prompt '\(prompt.title)' -> Selected choice: '\(key)'")
    }
}

// MARK: DynamicDestination

/// A destination tile of the flyout (upstream `DestinationTileViewModel`).
public struct RecipeFlyoutTile: Equatable, Sendable {
    public var designation: String
    public var title: String
    public var subtitle: String
    /// "Retry" on the Clipboard tile after a failed export (upstream).
    public var badge: String?
    /// The first group (Editor, Clipboard, Save As, Save, Printer, OCR, Share), else the searchable list.
    public var isCore: Bool

    public init(designation: String, title: String, subtitle: String, badge: String? = nil, isCore: Bool) {
        self.designation = designation
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.isCore = isCore
    }
}

/// What the flyout shows (upstream `DynamicDestinationStep` + `DynamicDestinationWindow`).
public struct RecipeFlyout: Equatable, Sendable {
    public var title: String
    public var showPreview: Bool
    public var timeoutSeconds: Int
    /// The failed export's message (variable `LastError`).
    public var errorMessage: String?
    public var tiles: [RecipeFlyoutTile]
    /// Recipes to forward the capture to: id and name.
    public var recipes: [RecipeForwardChoice]

    public struct RecipeForwardChoice: Equatable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// - Parameters:
    ///   - available: the destinations here as (designation, display name), the picker's order.
    ///   - recipes: the enabled recipes the capture could go to (the running one is left out).
    public init(_ step: RecipeStepInvocation, lastError: String?, available: [(designation: String, name: String)],
                recipes: [RecipeForwardChoice], runningRecipeId: String) {
        let given = step.string("Title")?.trimmingCharacters(in: .whitespaces) ?? ""
        title = given.isEmpty ? "Export Capture" : given
        showPreview = step.bool("ShowPreview") ?? true
        timeoutSeconds = max(step.int("TimeoutSeconds") ?? 0, 0)
        let error = lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        errorMessage = error.isEmpty ? nil : error
        let wanted = (step.strings("Destinations") ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var list = available.filter { !RecipeDestinationPlan.isPicker($0.designation) }
        if !wanted.isEmpty { list = list.filter { item in wanted.contains { recipeEquals($0, item.designation) } } }
        if !list.contains(where: { recipeEquals($0.designation, "Editor") }) {
            list.insert((designation: "Editor", name: "Open in Editor"), at: 0)
        }
        let hasError = errorMessage != nil
        let tiles = list.map { item -> RecipeFlyoutTile in
            let names = Self.names(item.designation, fallback: item.name)
            return RecipeFlyoutTile(designation: item.designation, title: names.title, subtitle: names.subtitle,
                                    badge: hasError && recipeEquals(item.designation, "Clipboard") ? "Retry" : nil,
                                    isCore: Self.isCore(item.designation))
        }
        let core = tiles.filter(\.isCore).enumerated().sorted { lhs, rhs in
            let left = Self.coreOrder(lhs.element.designation)
            let right = Self.coreOrder(rhs.element.designation)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        self.tiles = core + tiles.filter { !$0.isCore }
        let allowForwarding = step.bool("AllowRecipeForwarding") ?? true
        self.recipes = allowForwarding ? recipes.filter { !recipeEquals($0.id, runningRecipeId) } : []
    }

    /// The searchable tiles whose title or subtitle has `text` (all for an empty text).
    public func otherTiles(matching text: String) -> [RecipeFlyoutTile] {
        let others = tiles.filter { !$0.isCore }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return others }
        return others.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    public static func countdownText(_ seconds: Int) -> String {
        seconds > 0 ? "Auto-closing in \(seconds)s..." : ""
    }

    /// Upstream `IsCoreDestination`.
    static func isCore(_ designation: String) -> Bool {
        coreOrder(designation) < 10
    }

    /// Upstream `SortCoreDestinations`.
    static func coreOrder(_ designation: String) -> Int {
        let lower = designation.lowercased()
        switch lower {
        case "editor": return 1
        case "clipboard": return 2
        case "filedialog": return 3
        case "filenodialog": return 4
        case "printer": return 5
        default:
            if lower.contains("ocr") { return 6 }
            if lower.contains("share") { return 7 }
            return 10
        }
    }

    /// Upstream `FormatDestinationNames`, with the Mac's names.
    static func names(_ designation: String, fallback: String) -> (title: String, subtitle: String) {
        switch designation.lowercased() {
        case "clipboard": return ("Clipboard", "Copy image to clipboard")
        case "editor": return ("Editor", "Annotate and export")
        case "filenodialog", "file": return ("Save Directly", "Save to folder")
        case "filedialog", "fileas": return ("Save As…", "Choose folder & format")
        case "printer": return ("Printer", "Send to printer")
        case "windows10ocr", "ocr": return ("OCR Text", "Extract text from image")
        case "windows10share", "share": return ("Share", "Share with apps & contacts")
        case "email", "mail": return ("Email", "New email attachment")
        case "word": return ("Microsoft Word", "Insert into document")
        case "excel": return ("Microsoft Excel", "Insert into workbook")
        case "powerpoint": return ("Microsoft PowerPoint", "Insert into presentation")
        case "outlook": return ("Microsoft Outlook", "New email attachment")
        case "onenote", "notes": return ("Notes", "Add to a note")
        case "pdf": return ("PDF", "Save as PDF document")
        case "jira": return ("Jira", "Attach to an issue")
        case "confluence": return ("Confluence", "Attach to a page")
        case "box": return ("Box", "Upload to Box")
        case "dropbox": return ("Dropbox", "Upload to Dropbox")
        case "zxingqrdestination", "qrcode": return ("QR Code", "Read the QR code")
        case "openwith": return ("Open With", "Open in another app")
        default:
            if designation.lowercased().hasPrefix("external ") { return (String(designation.dropFirst("external ".count)), "External command") }
            return (fallback, designation)
        }
    }

    /// What was chosen.
    public enum Choice: Equatable, Sendable {
        case destination(String)
        case editor
        case forward(String)
        case dismissed
    }
}

/// The app's flyout and what it does with the choice.
public protocol RecipeFlyoutPresenting: Sendable {
    /// The destinations here (designation, display name), in the picker's order.
    func availableDestinations(in context: RecipeFlowContext) async -> [(designation: String, name: String)]
    /// The enabled recipes, id and name.
    func forwardableRecipes() async -> [RecipeFlyout.RecipeForwardChoice]
    /// Shows the flyout and waits; cancelling the task closes it.
    func choose(_ flyout: RecipeFlyout, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipeFlyout.Choice
    /// Exports to the chosen destination (or the editor) like a destination step with that one designation.
    func export(_ designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async throws
    /// Hands the capture to another recipe and waits for it (upstream runs it with the payload and the variables).
    func forward(to recipeId: String, in context: RecipeFlowContext) async
}

/// Upstream `DynamicDestinationStep`.
public struct RecipeDynamicDestinationExecutor: RecipeStepExecutor {
    let presenter: any RecipeFlyoutPresenting

    public init(presenter: any RecipeFlyoutPresenting) {
        self.presenter = presenter
    }

    public func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let available = await presenter.availableDestinations(in: context)
        let recipes = await presenter.forwardableRecipes()
        let flyout = RecipeFlyout(step, lastError: context[variable: "LastError"]?.asString, available: available, recipes: recipes,
                                  runningRecipeId: context.recipe.id)
        let preview = flyout.showPreview ? context.payload?.flattened() : nil
        switch try await presenter.choose(flyout, preview: preview, in: context) {
        case .editor:
            context.log("DynamicDestination: User selected Open in Editor.")
            try await presenter.export("Editor", step: step, in: context)
        case .destination(let designation):
            context.log("DynamicDestination: User selected destination '\(designation)'.")
            try await presenter.export(designation, step: step, in: context)
        case .forward(let recipeId):
            context.log("DynamicDestination: Forwarding capture to recipe '\(recipeId)'.")
            await presenter.forward(to: recipeId, in: context)
        case .dismissed:
            context.log("DynamicDestination: Flyout dismissed without destination selection.")
        }
    }
}

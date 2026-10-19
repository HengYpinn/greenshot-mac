// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("RecipeEditor")

/// What the editor works with besides the recipe: the running app's recipes (nil before they start and in
/// `--snapshot`), the step contracts and the settings the gate checks read.
@MainActor
struct RecipeEditorEnvironment {
    var runtime: () -> RecipeRuntime?
    var gates: () -> GateEnvironment
    /// The names of Settings › Destinations' external commands (for `External <name>` designations and the
    /// ExternalCommand step's `Command`).
    var externalCommandNames: () -> [String]

    var library: RecipeLibrary? { runtime()?.library }
    var contracts: StepContractCatalog { runtime()?.steps.contracts ?? .builtIn }

    /// Whether the app can run steps of this type (the toolbox greys out the others); everything without a runtime.
    func hasExecutor(_ stepType: String) -> Bool {
        guard let runtime = runtime() else { return true }
        return runtime.steps.executor(for: stepType) != nil
    }

    /// The running app: `RecipeRuntime.shared` and the settings of the app delegate.
    static var live: RecipeEditorEnvironment {
        RecipeEditorEnvironment(
            runtime: { RecipeRuntime.shared },
            gates: { (NSApp.delegate as? AppDelegate).map { GateEnvironment(settings: $0.settings.value) } ?? .empty },
            externalCommandNames: { (NSApp.delegate as? AppDelegate)?.settings.value.externalCommands.map(\.name) ?? [] })
    }

    /// No runtime (snapshots).
    static var offline: RecipeEditorEnvironment {
        RecipeEditorEnvironment(runtime: { nil }, gates: { .empty }, externalCommandNames: { ["MS Paint", "Optimize PNG"] })
    }
}

/// The recipe editor's state (upstream RecipeEditorViewModel.cs): a copy of one recipe or automatic step, what was saved,
/// the selection, validation, the pending-approval notice and the undo history. Changes reach Greenshot only through
/// `save` (the library's edit approval).
@MainActor
final class RecipeEditorModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case step = "Step"
        case recipe = "Recipe"
        case triggers = "Triggers"
        case options = "Options"
        case errors = "Error Routes"
        case json = "JSON"
        case flow = "Flow"

        var id: String { rawValue }

        /// The tab's title (the raw value is its identifier).
        var title: String {
            switch self {
            case .step: return String(localized: "Step")
            case .recipe: return String(localized: "Recipe")
            case .triggers: return String(localized: "Triggers")
            case .options: return String(localized: "Options")
            case .errors: return String(localized: "Error Routes")
            case .json: return String(localized: "JSON")
            case .flow: return String(localized: "Flow")
            }
        }
    }

    let environment: RecipeEditorEnvironment
    /// The editor window, for sheets.
    weak var window: NSWindow?

    @Published private(set) var recipe: CaptureRecipe?
    @Published private(set) var outline = RecipeOutline(CaptureRecipe(id: "", name: ""))
    @Published var selectedRow: String?
    @Published var tab: Tab = .step
    @Published private(set) var validation = RecipeValidationResult()
    @Published private(set) var diagnostics: [RecipeDiagnostic] = []
    /// The pending bar (upstream `ApprovalNotice`).
    @Published private(set) var notice: String?
    /// The notice is about the saved file: "Review approval…" is offered.
    @Published private(set) var canReviewApproval = false
    @Published var status = ""
    @Published private(set) var isDirty = false
    @Published private(set) var fileURL: URL?
    /// SHA-256 of the file bytes the recipe was loaded from (`openFile`); the library compares it with the approved bytes,
    /// as the file on disk at save time could have been put back. Nil for a recipe that wasn't read from a file here.
    var loadedSha256: String?
    @Published var showAllParameters = false
    /// Bumped when the library changed (the recipe picker and the header read the library).
    @Published private(set) var libraryRevision = 0
    /// The JSON tab's text while it differs from the recipe and isn't applied (nil: none).
    @Published var jsonDraft: String?
    /// The recipe's content when the JSON draft was started: the recipe changed since when they differ.
    private(set) var jsonDraftBase: String?
    /// The open copy came from a file the library didn't load (rejected, or opened to fix it): its first save shows the
    /// approval window.
    private(set) var openedUnapproved = false

    /// The content as saved; nil while it was never saved (upstream `_savedContent`).
    private var savedContent: String?
    /// The open copy is the one Greenshot has loaded (so it follows the library while there are no unsaved changes).
    private var openedFromLibrary = false

    /// The id(s) of the recipe as last saved (a rename of the id isn't "another recipe" of its own file).
    var savedRecipeIds: [String] {
        guard let savedContent, let saved = try? RecipeSerializer.decode(text: savedContent) else { return [] }
        return saved.map(\.id)
    }
    private var history = RecipeEditHistory()
    private var checkTimer: Timer?
    private var libraryObservation: RecipeObservation?

    init(environment: RecipeEditorEnvironment) {
        self.environment = environment
    }

    var library: RecipeLibrary? { environment.library }
    var contracts: StepContractCatalog { environment.contracts }
    var isExtension: Bool { recipe?.kind == .extension }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// The recipe as it would be saved now.
    var content: String? { recipe.map { RecipeSerializer.encode($0) } }

    /// Starts following the library's changes (the pending bar, the header, the recipe picker).
    func observeLibrary() {
        guard libraryObservation == nil, let runtime = environment.runtime() else { return }
        libraryObservation = runtime.addChangeObserver { [weak self] in self?.libraryChanged() }
    }

    func stopObserving() {
        libraryObservation?.cancel()
        libraryObservation = nil
        checkTimer?.invalidate()
    }

    private func libraryChanged() {
        libraryRevision += 1
        refreshFromLibrary()
        refreshNotice()
    }

    /// Upstream `RefreshAvailableRecipes`: without unsaved changes the editor shows what Greenshot has. A recipe that was
    /// reset, changed outside and approved again, or saved elsewhere is opened again; one that is gone gives way to the
    /// first recipe. A copy Greenshot never had (a new recipe, a file it didn't load) stays.
    func refreshFromLibrary() {
        guard let library, let recipe, !isDirty, jsonDraft == nil else { return }
        let loaded = library.recipe(id: recipe.id)
            ?? library.extensions.first { $0.recipe.id.caseInsensitiveCompare(recipe.id) == .orderedSame }
        guard let loaded else {
            if openedFromLibrary {
                if let first = library.recipes.first {
                    open(first.recipe, fileURL: first.sourceFile, saved: true)
                } else {
                    close()
                }
                let name = recipe.name
                status = String(localized: "\(name) is no longer loaded in Greenshot.")
            }
            return
        }
        let samePlace = loaded.sourceFile.map { RecipeEditorFiles.standardized($0).path } == fileURL.map { RecipeEditorFiles.standardized($0).path }
        guard !samePlace || RecipeSerializer.encode(loaded.recipe) != savedContent else { return }
        open(loaded.recipe, fileURL: loaded.sourceFile, saved: true, keepSelection: true)
        let name = loaded.recipe.name
        status = String(localized: "Showing \(name) as Greenshot has it now.")
    }

    // MARK: Opening

    /// Puts a copy of `recipe` into the editor (upstream `OpenWorkingCopy`); `saved`: it is what the file (or the
    /// built-in) holds, so it starts without unsaved changes.
    func open(_ recipe: CaptureRecipe, fileURL: URL?, saved: Bool, keepSelection: Bool = false) {
        history.keep(recipeId: self.recipe?.id)
        let text = RecipeSerializer.encode(recipe)
        let selection = selectedRow
        self.recipe = recipe
        self.fileURL = fileURL
        loadedSha256 = nil
        savedContent = saved ? text : nil
        jsonDraft = nil
        jsonDraftBase = nil
        openedUnapproved = false
        openedFromLibrary = environment.library.map { library in
            (library.recipe(id: recipe.id) ?? library.extensions.first { $0.recipe.id.caseInsensitiveCompare(recipe.id) == .orderedSame })
                .map { RecipeSerializer.encode($0.recipe) == text } ?? false
        } ?? false
        history.reset(recipeId: recipe.id, content: text)
        outline = RecipeOutline(recipe)
        if keepSelection, let selection, outline.rows.contains(where: { $0.id == selection }) {
            selectedRow = selection
        } else {
            selectedRow = outline.rows.first { $0.nodeId != nil }?.id
            if !keepSelection { tab = .step }
        }
        recomputeState()
        refreshNotice()
    }

    /// A file's copy the library didn't load (rejected, or opened to fix it).
    func openUnapproved(_ recipe: CaptureRecipe, fileURL: URL) {
        open(recipe, fileURL: fileURL, saved: true)
        openedUnapproved = true
    }

    /// Nothing open (after "Don't Save" of a recipe that was never saved).
    func close() {
        history.keep(recipeId: recipe?.id)
        recipe = nil
        fileURL = nil
        loadedSha256 = nil
        savedContent = nil
        jsonDraft = nil
        openedUnapproved = false
        openedFromLibrary = false
        outline = RecipeOutline(CaptureRecipe(id: "", name: ""))
        selectedRow = nil
        recomputeState()
        refreshNotice()
    }

    /// The recipe or automatic step with this id from the library.
    func open(recipeId: String) -> Bool {
        guard let library else { return false }
        if let loaded = library.recipe(id: recipeId) {
            open(loaded.recipe, fileURL: loaded.sourceFile, saved: true)
            return true
        }
        if let loaded = library.extensions.first(where: { $0.recipe.id.caseInsensitiveCompare(recipeId) == .orderedSame }) {
            open(loaded.recipe, fileURL: loaded.sourceFile, saved: true)
            return true
        }
        return false
    }

    // MARK: Changing

    /// Every change of the recipe goes through here.
    func edit(_ status: String? = nil, _ change: (inout CaptureRecipe) -> Void) {
        guard var changed = recipe else { return }
        change(&changed)
        guard changed != recipe else { return }
        recipe = changed
        if let status { self.status = status }
        afterChange()
    }

    private func afterChange() {
        guard let recipe else { return }
        outline = RecipeOutline(recipe)
        recomputeState()
        if let content { history.record(content, force: false) }
        scheduleCheck()
    }

    /// Upstream `RefreshUnsavedState`, a moment after the last change: records the change in the history once it stopped
    /// changing and asks the library what saving would ask for.
    private func scheduleCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        if let content { history.record(content, force: false) }
        refreshNotice()
        objectWillChange.send()
    }

    private func recomputeState() {
        guard let recipe else {
            isDirty = false
            validation = RecipeValidationResult()
            diagnostics = []
            return
        }
        let text = RecipeSerializer.encode(recipe)
        isDirty = savedContent == nil || savedContent != text
        let result = RecipeValidator(contracts: contracts, gates: environment.gates()).validate(recipe)
        validation = result
        diagnostics = RecipeEditorDiagnostics.diagnostics(of: result, in: recipe)
        updateWindow()
    }

    /// The title is the recipe's name, the close button shows unsaved changes (upstream's "*"), the proxy icon its file.
    func updateWindow() {
        guard let window else { return }
        let name = recipe?.name ?? ""
        window.title = name.isEmpty ? String(localized: "Recipe Editor") : name
        window.subtitle = isExtension ? String(localized: "Automatic Step — Recipe Editor") : String(localized: "Recipe Editor")
        window.representedURL = fileURL
        window.isDocumentEdited = isDirty
    }

    func refreshNotice() {
        guard let library, let recipe else {
            notice = nil
            canReviewApproval = false
            return
        }
        if isDirty {
            let reasons = recipe.kind == .extension ? library.extensionSaveDecisionReasons(for: recipe, at: fileURL)
                : library.saveDecisionReasons(for: recipe, at: fileURL, loadedSha256: loadedSha256)
            notice = RecipeEditorDiagnostics.saveNotice(reasons: reasons)
            canReviewApproval = false
            return
        }
        guard recipe.kind == .recipe, library.recipe(id: recipe.id) != nil else {
            notice = nil
            canReviewApproval = false
            return
        }
        let exists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        notice = RecipeEditorDiagnostics.approvalNotice(details: library.details(recipeId: recipe.id), fileExists: exists)
        canReviewApproval = notice != nil && fileURL != nil
    }

    // MARK: Undo

    func undo() {
        guard let content, let target = history.undo(from: content) else { return }
        restore(target)
        status = String(localized: "Undone")
    }

    func redo() {
        guard let content, let target = history.redo(from: content) else { return }
        restore(target)
        status = String(localized: "Redone")
    }

    private func restore(_ text: String) {
        guard let restored = try? RecipeSerializer.decode(text: text).first else {
            log.warn("An undo state of the recipe editor could not be read.")
            return
        }
        let selection = selectedRow
        recipe = restored
        outline = RecipeOutline(restored)
        selectedRow = outline.rows.contains { $0.id == selection } ? selection : outline.rows.first { $0.nodeId != nil }?.id
        history.didRestore(RecipeSerializer.encode(restored))
        recomputeState()
        refreshNotice()
    }

    /// Upstream `ApplyJson`: the recipe from the JSON tab; undo goes back to before it.
    func applyJSON(_ text: String) -> String? {
        guard let current = recipe else { return nil }
        let parsed: [CaptureRecipe]
        do {
            parsed = try RecipeSerializer.decode(text: text)
        } catch {
            let problem = (error as? RecipeFormatError)?.message ?? error.localizedDescription
            return String(localized: "Invalid JSON syntax or schema:\n\(problem)")
        }
        guard parsed.count == 1, let applied = parsed.first else {
            let count = parsed.count
            return String(localized: "The JSON must hold exactly one recipe (it holds \(count)).")
        }
        guard applied.kind == current.kind else {
            return applied.kind == .extension ? String(localized: "This is an automatic step; the editor has a recipe open.")
                : String(localized: "This is a recipe; the editor has an automatic step open.")
        }
        if let content { history.record(content, force: true) }
        recipe = applied
        outline = RecipeOutline(applied)
        recomputeState()
        if let content { history.record(content, force: true) }
        refreshNotice()
        jsonDraft = nil
        jsonDraftBase = nil
        status = String(localized: "Applied recipe JSON changes.")
        return nil
    }

    // MARK: Selection

    var selectedOutlineRow: RecipeOutlineRow? {
        guard let selectedRow else { return nil }
        return outline.rows.first { $0.id == selectedRow }
    }

    var selectedNode: RecipeNode? {
        guard let id = selectedOutlineRow?.nodeId else { return nil }
        return recipe?.node(id)
    }

    func select(nodeId: String) {
        selectedRow = RecipeOutlineRow.stepId(nodeId)
        tab = .step
    }

    // MARK: Steps

    /// Upstream `AddStep`: into the selected arrow, branch or lane, after the selected step, else at the end.
    func addStep(_ stepType: String) {
        guard let recipe else { return }
        let row = selectedOutlineRow
        var previous: String?
        var next: String?
        switch row?.kind {
        case .step(let id)?:
            previous = id
            next = recipe.flow.targets(from: id).first
        case .continues(let from, _, let to)?:
            previous = from
            next = to
        case .lane(let from, _, let target)?:
            previous = from
            next = target
        default:
            break
        }
        let node = RecipeEditorCatalog.newNode(stepType, in: recipe, previous: previous, next: next, contracts: contracts)
        let added = node.displayName
        edit(String(localized: "Added step: \(added)")) { recipe in
            switch row?.kind {
            case .step(let id)?:
                if let selected = recipe.node(id), RecipeOutline.isDecision(selected),
                   let key = RecipeOutline.branches(of: selected, in: recipe.flow).first?.key {
                    RecipeFlowEditor.insert(node, intoBranch: key, of: id, in: &recipe)
                } else {
                    RecipeFlowEditor.insert(node, after: id, in: &recipe)
                }
            case .branch(let from, let key, _, _)?:
                RecipeFlowEditor.insert(node, intoBranch: key, of: from, in: &recipe)
            case .lane(let from, _, let target)?:
                RecipeFlowEditor.insert(node, between: from, and: target, branch: nil, in: &recipe)
            case .continues(let from?, let branch, let to)?:
                RecipeFlowEditor.insert(node, between: from, and: to, branch: branch, in: &recipe)
            case .parallel(let from)?:
                RecipeFlowEditor.addParallel(node, from: from, in: &recipe)
            case .extensionOut(let from, _)?:
                RecipeFlowEditor.insert(node, after: from, in: &recipe)
            default:
                RecipeFlowEditor.append(node, in: &recipe)
            }
        }
        select(nodeId: node.id)
    }

    /// Inserts a step of `stepType` at a place of the outline (the rows' "+" buttons and menus).
    func insertStep(_ stepType: String, at place: InsertPlace) {
        guard let recipe else { return }
        var previous: String?
        var next: String?
        switch place {
        case .after(let id): previous = id; next = recipe.flow.targets(from: id).first
        case .between(let from, let to, _): previous = from; next = to
        case .branch(let decision, _): previous = decision
        case .parallel(let from): previous = from
        }
        let node = RecipeEditorCatalog.newNode(stepType, in: recipe, previous: previous, next: next, contracts: contracts)
        let added = node.displayName
        edit(String(localized: "Added step: \(added)")) { recipe in
            switch place {
            case .after(let id): RecipeFlowEditor.insert(node, after: id, in: &recipe)
            case .between(let from, let to, let branch): RecipeFlowEditor.insert(node, between: from, and: to, branch: branch, in: &recipe)
            case .branch(let decision, let key): RecipeFlowEditor.insert(node, intoBranch: key, of: decision, in: &recipe)
            case .parallel(let from): RecipeFlowEditor.addParallel(node, from: from, in: &recipe)
            }
        }
        select(nodeId: node.id)
    }

    enum InsertPlace {
        case after(String)
        case between(from: String?, to: String, branch: String?)
        case branch(decision: String, key: String)
        case parallel(from: String?)
    }

    /// Upstream `DeleteSelected`: the selected step, or the selected "continues at" connection.
    func deleteSelection() {
        guard let row = selectedOutlineRow else { return }
        switch row.kind {
        case .step(let id):
            deleteStep(id)
        case .continues(let from, let branch, let to):
            disconnect(from: from, to: to, branch: branch)
        case .extensionOut(let from, let branch):
            disconnect(from: from, to: "Out", branch: branch)
        default:
            break
        }
    }

    func deleteStep(_ id: String) {
        let order = outline.stepOrder
        let position = order.firstIndex { $0.caseInsensitiveCompare(id) == .orderedSame } ?? 0
        let name = recipe?.node(id)?.displayName ?? id
        edit(String(localized: "Deleted step '\(name)' (\(id))")) { RecipeFlowEditor.delete(id, in: &$0) }
        let remaining = outline.stepOrder
        if !remaining.isEmpty { selectedRow = RecipeOutlineRow.stepId(remaining[min(position, remaining.count - 1)]) }
    }

    func disconnect(from: String?, to: String, branch: String?) {
        edit(String(localized: "Removed the connection to '\(to)'")) { RecipeFlowEditor.disconnect(from: from, to: to, branch: branch, in: &$0) }
    }

    func retarget(from: String?, branch: String?, old: String, new: String) {
        guard let recipe else { return }
        var copy = recipe
        guard RecipeFlowEditor.retarget(from: from, branch: branch, old: old, new: new, in: &copy) else {
            status = String(localized: "'\(new)' can't follow there: the flow would loop.")
            return
        }
        edit(String(localized: "Continues at '\(new)'")) { $0 = copy }
    }

    func connect(from: String, to: String, branch: String?) {
        guard let recipe else { return }
        var copy = recipe
        guard RecipeFlowEditor.connect(from: from, to: to, branch: branch, in: &copy) else {
            status = String(localized: "'\(to)' can't follow '\(from)': the flow would loop.")
            return
        }
        edit(String(localized: "Connected '\(from)' to '\(to)'")) { $0 = copy }
    }

    func toggleStart(_ id: String) {
        let isStart = recipe.map { RecipeFlowEditor.isStart(id, in: $0) } ?? false
        let message = isStart ? String(localized: "'\(id)' is no longer a start step") : String(localized: "'\(id)' is a start step")
        edit(message) { RecipeFlowEditor.toggleStart(id, in: &$0) }
    }

    func move(_ id: String, up: Bool) {
        guard let recipe else { return }
        var copy = recipe
        let moved = up ? RecipeFlowEditor.moveUp(id, in: &copy) : RecipeFlowEditor.moveDown(id, in: &copy)
        guard moved else {
            status = String(localized: "Only steps in a plain sequence can move.")
            return
        }
        edit(up ? String(localized: "Moved '\(id)' up") : String(localized: "Moved '\(id)' down")) { $0 = copy }
        select(nodeId: id)
    }

    /// Upstream `HandleNodeIdChanged`.
    func rename(_ old: String, to new: String) {
        guard let recipe else { return }
        var copy = recipe
        do {
            try RecipeFlowEditor.rename(old, to: new, in: &copy)
        } catch {
            status = error.localizedDescription
            return
        }
        guard copy != recipe else { return }
        let renamed = new.trimmingCharacters(in: .whitespaces)
        edit(String(localized: "Renamed step ID from '\(old)' to '\(renamed)'")) { $0 = copy }
        select(nodeId: new.trimmingCharacters(in: .whitespaces))
    }

    /// Changes one step.
    func editNode(_ id: String, _ status: String? = nil, _ change: (inout RecipeNode) -> Void) {
        edit(status) { recipe in
            guard let index = recipe.nodes.firstIndex(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return }
            change(&recipe.nodes[index])
        }
    }

    /// The diagnostics about a target.
    func diagnostics(for target: RecipeDiagnosticTarget) -> [RecipeDiagnostic] {
        diagnostics.filter { $0.target == target }
    }

    /// Opens a new recipe (upstream `NewRecipe`); never saved, so it has unsaved changes.
    func newRecipe() {
        open(RecipeEditorCatalog.newRecipe(), fileURL: nil, saved: false)
        status = String(localized: "Created new recipe.")
    }

    func newExtension() {
        open(RecipeEditorCatalog.newExtension(), fileURL: nil, saved: false)
        status = String(localized: "Created a new automatic step: put its steps before Out, set where it goes in the Recipe tab.")
    }

    /// After a save: the saved content is what the editor has.
    /// After a save: `savedText` is what the library wrote (edits made while its approval window was open stay unsaved).
    func markSaved(at url: URL, savedText: String) {
        fileURL = url
        loadedSha256 = nil
        savedContent = savedText
        openedUnapproved = false
        openedFromLibrary = true
        recomputeState()
        refreshNotice()
    }

    /// Snapshots: a pending-bar text as the library would give it (there is no library in `--snapshot`).
    func showNotice(_ text: String?, canReview: Bool) {
        notice = text
        canReviewApproval = canReview
    }

    /// "Don't Save": the copy's changes are dropped from the dirty state (upstream `ConfirmDiscardChanges` case 1).
    /// "Don't Save": back to the content as saved; a recipe that was never saved shows what Greenshot has of it, or
    /// nothing (upstream's window isn't reused, so it only forgets the changes).
    func discardChanges() {
        jsonDraft = nil
        jsonDraftBase = nil
        if let savedContent, let saved = try? RecipeSerializer.decode(text: savedContent).first {
            let unapproved = openedUnapproved
            let fromLibrary = openedFromLibrary
            open(saved, fileURL: fileURL, saved: true, keepSelection: true)
            openedUnapproved = unapproved
            openedFromLibrary = fromLibrary
        } else if let id = recipe?.id, let loaded = library?.recipe(id: id) {
            open(loaded.recipe, fileURL: loaded.sourceFile, saved: true, keepSelection: true)
        } else {
            close()
        }
    }

    // MARK: JSON tab

    /// The JSON tab's text changed: a draft while it differs from the recipe.
    func setJSONDraft(_ text: String) {
        if text == content {
            jsonDraft = nil
            jsonDraftBase = nil
        } else {
            if jsonDraft == nil { jsonDraftBase = content }
            jsonDraft = text
        }
    }

    /// The recipe changed (undo, a form) after the JSON draft was started.
    var jsonDraftIsStale: Bool { jsonDraft != nil && jsonDraftBase != content }

    func discardJSONDraft() {
        jsonDraft = nil
        jsonDraftBase = nil
    }
}

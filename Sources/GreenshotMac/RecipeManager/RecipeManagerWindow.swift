// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI
import UniformTypeIdentifiers

/// What the recipe manager shows and does (upstream `Greenshot.Plugin.RecipeEditor/ViewModels/RecipeManagerViewModel.cs`):
/// the recipes and the automatic steps, filtered and searched, and the actions on them.
@MainActor
final class RecipeManagerModel: ObservableObject {
    let library: RecipeLibrary
    /// Nil in `--snapshot`: no test runs.
    private weak var runtime: RecipeRuntime?
    @Published private(set) var recipes: [RecipeManagerItem] = []
    @Published private(set) var extensions: [RecipeManagerItem] = []
    @Published var filter: RecipeManagerFilter = .all
    @Published var query = ""
    @Published var selection: String?
    @Published var status = ""
    /// Closes the window (after Edit and New Recipe, like upstream).
    var close: (() -> Void)?
    private var observation: RecipeObservation?

    init(library: RecipeLibrary, runtime: RecipeRuntime?) {
        self.library = library
        self.runtime = runtime
        refresh()
        observation = runtime?.addChangeObserver { [weak self] in self?.refresh() }
    }

    func refresh() {
        let items = library.managerItems()
        recipes = items.recipes
        extensions = items.extensions
        if selection == nil || !(recipes + extensions).contains(where: { $0.id == selection }) {
            selection = filteredRecipes.first?.id
        }
    }

    var filteredRecipes: [RecipeManagerItem] { RecipeManagerList.filter(recipes, by: filter, query: query) }
    var filteredExtensions: [RecipeManagerItem] { RecipeManagerList.filter(extensions, by: filter, query: query) }
    var counts: (total: Int, active: Int, deactivated: Int) { RecipeManagerList.counts(recipes) }
    var canTestRun: Bool { runtime != nil }
    var anyOverridden: Bool { recipes.contains { $0.isOverridden } }

    func select(_ id: String) {
        filter = .all
        query = ""
        selection = id
    }

    // MARK: A row

    func toggle(_ item: RecipeManagerItem) {
        if item.isExtension {
            guard item.canToggle else { return }
            library.setExtensionEnabled(!item.isEnabled, id: item.id)
        } else {
            library.setEnabled(!item.isEnabled, recipeId: item.id)
        }
        refresh()
    }

    func edit(_ item: RecipeManagerItem) {
        if item.isExtension {
            RecipeEditorService.openExtension(id: item.id)
        } else {
            RecipeEditorService.openEditor(recipeId: item.id)
        }
        close?()
    }

    /// Upstream `ExecuteTestRunAsync`: runs it for real with the manual trigger.
    func testRun(_ item: RecipeManagerItem) {
        guard !item.isExtension, let runtime, let loaded = library.recipe(id: item.id) else { return }
        let validation = loaded.validation.isValid ? RecipeValidator().validate(loaded.recipe) : loaded.validation
        guard validation.isValid else {
            Self.alert("Validation Error", "Cannot test run recipe. Fix validation errors first:\n\n" + validation.errors.joined(separator: "\n"))
            return
        }
        guard var request = library.runRequest(recipeId: item.id, triggerType: WellKnownTriggerType.manual) else { return }
        request.trigger = RecipeRuntime.triggerInfo(type: WellKnownTriggerType.manual)
        let handle = runtime.start(request)
        status = "Test run of \(item.name) started."
        Task { [weak self] in
            let result = await handle.result
            guard let self else { return }
            if result.state == .failed {
                let message = [result.reason, result.errorDescription].compactMap { $0 }.joined(separator: "\n")
                Self.alert("Execution Error", "Recipe execution encountered an error:\n\(message)")
                self.status = "Test run of \(item.name) failed."
            } else {
                self.status = "Test run of \(item.name): \(result.state == .completed ? "completed" : "cancelled")."
            }
        }
    }

    func details(_ item: RecipeManagerItem) {
        Task { await library.showDetails(id: item.id) }
    }

    /// "Permissions": the approval sheet in review mode ("Save Changes", "Keep as Is", "Revoke Approval").
    func permissions(_ item: RecipeManagerItem) {
        guard item.hasFile else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = item.isExtension ? await self.library.reviewExtensionApproval(id: item.id)
                                          : await self.library.reviewApproval(recipeId: item.id)
            if !result.isValid {
                Self.alert("Recipe Permissions", result.errors.joined(separator: "\n"))
            }
            self.refresh()
        }
    }

    func unload(_ item: RecipeManagerItem) {
        guard item.canUnload else { return }
        let reset = item.isOverridden && !item.isExtension
        let title = reset ? "Reset Recipe to Default" : (item.isExtension ? "Unload Automatic Step" : "Unload Recipe")
        let message = reset ? "Are you sure you want to revert '\(item.name)' back to its default built-in definition?"
                            : "Are you sure you want to unload '\(item.name)'? It will be unregistered from \(AppInfo.name)."
        guard Self.confirm(title, message, button: reset ? "Reset" : "Unload") else { return }
        if item.isExtension {
            library.unloadExtension(id: item.id)
        } else if reset {
            library.resetToDefault(recipeId: item.id)
        } else {
            library.unload(recipeId: item.id)
        }
        refresh()
    }

    func revealInFinder(_ item: RecipeManagerItem) {
        guard let path = item.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: The toolbar

    func loadRecipe() {
        let panel = NSOpenPanel()
        panel.title = "Load Capture Recipe into \(AppInfo.name)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.library.loadFile(url)
            if result.isValid {
                self.status = "Loaded and registered \(url.lastPathComponent)"
                self.refresh()
                if let id = result.loadedRecipeIds.first { self.select(id) }
            } else {
                Self.alert("Validation Error", "Failed to load recipe:\n\n" + result.errors.joined(separator: "\n"))
                self.status = "Validation failed for \(url.lastPathComponent)"
                self.refresh()
            }
        }
    }

    func newRecipe() {
        RecipeEditorService.newRecipe()
        close?()
    }

    func reloadAll() {
        Task { [weak self] in
            guard let self else { return }
            if let runtime = self.runtime {
                _ = await runtime.reload()
            } else {
                _ = await self.library.reload()
            }
            self.status = "Reloaded recipes from disk."
            self.refresh()
        }
    }

    /// Brings back every built-in recipe a file replaces.
    func resetAll() {
        let replaced = recipes.filter(\.isOverridden).map(\.name)
        guard !replaced.isEmpty,
              Self.confirm("Reset All to Default", "Bring back the built-in version of these recipes?\n\n" + replaced.joined(separator: "\n"),
                           button: "Reset All") else { return }
        library.resetAllToDefault()
        refresh()
    }

    // MARK: Messages

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    private static func confirm(_ title: String, _ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// The recipe manager (RCP-255..259, RCP-261, RCP-262, R2-001; upstream `RecipeManagerWindow.xaml`): search, the
/// category chips, the recipes and the automatic steps as cards with their actions, the counters.
struct RecipeManagerView: View {
    @ObservedObject var model: RecipeManagerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        groupHeader("RECIPES", note: nil)
                        if model.filteredRecipes.isEmpty {
                            Text("No recipe matches.").foregroundStyle(.secondary).padding(.vertical, 4)
                        }
                        ForEach(model.filteredRecipes) { item in row(item) }
                        if !model.filteredExtensions.isEmpty {
                            groupHeader("AUTOMATIC STEPS",
                                        note: "Steps \(AppInfo.name) adds to the recipes with a fitting slot, switched in Settings › Recipes.")
                                .padding(.top, 8)
                            ForEach(model.filteredExtensions) { item in row(item) }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.selection) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func row(_ item: RecipeManagerItem) -> some View {
        RecipeManagerRow(item: item, isSelected: model.selection == item.id, model: model)
            .id(item.id)
            .onTapGesture { model.selection = item.id }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture Recipe Manager").font(.title2.weight(.semibold))
                    Text("The recipes and automatic steps \(AppInfo.name) knows.").foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search name, id, triggers, file", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }
            HStack(spacing: 8) {
                Button("Load Recipe…", action: model.loadRecipe)
                    .help("Load and register a .gsrecipe.json file")
                Button("New Recipe", action: model.newRecipe)
                    .help("Create a new capture recipe in the recipe editor")
                Button("Reload All", action: model.reloadAll)
                    .help("Reload the configured recipe files from disk")
                Button("Reset All", action: model.resetAll)
                    .help("Bring back the built-in version of every recipe a file replaces")
                    .disabled(!model.anyOverridden)
                Spacer()
                Picker("Show", selection: $model.filter) {
                    ForEach(RecipeManagerFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 400)
                .help("AI: recipes written by AI tools")
            }
        }
        .padding(16)
    }

    private func groupHeader(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        let counts = model.counts
        return HStack(spacing: 14) {
            Text("Total: \(counts.total)").fontWeight(.semibold)
            Text("Active: \(counts.active)")
            Text("Deactivated: \(counts.deactivated)")
            Text(model.status).italic().foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Close") { model.close?() }
                .keyboardShortcut(.cancelAction)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One recipe or automatic step as a card (upstream's item template).
struct RecipeManagerRow: View {
    let item: RecipeManagerItem
    let isSelected: Bool
    @ObservedObject var model: RecipeManagerModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.toggle(item) } label: {
                HStack(spacing: 5) {
                    Circle().fill(item.isEnabled ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(item.statusBadge).font(.caption2.weight(.bold))
                }
                .frame(width: 96)
            }
            .disabled(!item.canToggle)
            .help(item.isExtension ? "Switch the automatic step on or off (also in Settings › Recipes)" : "Click to activate or deactivate")
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                if !item.description.isEmpty {
                    Text(item.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    Label(item.triggersSummary, systemImage: item.isExtension ? "puzzlepiece.extension" : "bolt")
                        .lineLimit(2)
                    Label(item.stepCount == 1 ? "1 step" : "\(item.stepCount) steps", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(.caption)
                .foregroundStyle(item.hasUnapprovedTriggers ? Color.orange : Color.secondary)
                if let path = item.filePath {
                    Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(path)
                }
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor)))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") { model.revealInFinder(item) }.disabled(item.filePath == nil)
            Button("Copy Recipe ID") { model.copy(item.id) }
            Button("Copy File Path") { model.copy(item.filePath ?? "") }.disabled(item.filePath == nil)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(item.name).font(.headline)
            badge(item.typeBadge, color: item.isOverridden ? .orange : (item.isBuiltIn ? .blue : .purple))
            if let tool = item.proposedBy, item.isAICreated {
                badge("BY \(tool.uppercased())", color: .teal)
                    .help("Written by an AI tool and approved by you")
            }
            Text("v\(item.version)").font(.caption).foregroundStyle(.secondary)
            Text("(\(item.id))").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button("Edit") { model.edit(item) }
                .help(item.isExtension ? "Edit the automatic step in the recipe editor" : "Open the recipe in the recipe editor")
            if !item.isExtension {
                Button("Test Run") { model.testRun(item) }
                    .disabled(!model.canTestRun)
                    .help("Run the capture recipe now")
            }
            Button("Details") { model.details(item) }
                .help("What it does, its triggers, its approval and the changes against the built-in version")
            Button("Permissions") { model.permissions(item) }
                .disabled(!item.hasFile)
                .help("Switch the triggers and permissions of the approval on or off")
            Button(item.unloadTitle) { model.unload(item) }
                .disabled(!item.canUnload)
                .help(item.unloadTitle == "Reset Default" ? "Bring back the built-in version" : "Unload and forget the file")
        }
        .controlSize(.small)
        .padding(.top, 2)
    }
}

/// The manager's window: one, reused (upstream opens one manager).
@MainActor
final class RecipeManagerWindowController: DiagnosticsWindowController {
    let model: RecipeManagerModel
    private static var shared: RecipeManagerWindowController?

    init(model: RecipeManagerModel) {
        self.model = model
        super.init(title: "\(AppInfo.name) — Recipe Manager", content: RecipeManagerView(model: model),
                   size: NSSize(width: 900, height: 680), resizable: true, autosaveName: "GreenshotRecipeManager")
        model.close = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    static func show(library: RecipeLibrary, runtime: RecipeRuntime?, selecting recipeId: String?) {
        let controller = shared ?? RecipeManagerWindowController(model: RecipeManagerModel(library: library, runtime: runtime))
        shared = controller
        controller.model.refresh()
        if let recipeId { controller.model.select(recipeId) }
        controller.present()
    }
}

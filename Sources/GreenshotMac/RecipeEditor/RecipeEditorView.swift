// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The recipe editor (upstream Views/RecipeEditorWindow.xaml, as a list instead of a node canvas): toolbar, the active
/// recipe's header and pending bar, the step list on the left, the tabs on the right, the status line.
struct RecipeEditorView: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 0) {
            RecipeEditorTop(model: model)
            Divider()
            if model.recipe == nil {
                RecipeEditorEmptyState(model: model)
            } else {
                HSplitView {
                    RecipeEditorSidebar(model: model)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
                    RecipeEditorDetail(model: model)
                        .frame(minWidth: 480, maxWidth: .infinity)
                }
            }
            Divider()
            RecipeEditorStatusLine(model: model)
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

/// The toolbar, the active recipe's header and the pending bar.
struct RecipeEditorTop: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 0) {
            RecipeEditorToolbar(model: model)
            Divider()
            RecipeEditorHeader(model: model)
            if let notice = model.notice {
                RecipePendingBar(model: model, notice: notice)
            }
        }
    }
}

// MARK: Toolbar

private struct RecipeEditorToolbar: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        HStack(spacing: 8) {
            RecipePickerMenu(model: model)
            Divider().frame(height: 18)
            Menu {
                Button("New Recipe") { Task { await model.newRecipeAsking() } }
                Button("New Automatic Step") { Task { await model.newExtensionAsking() } }
            } label: {
                Label("New", systemImage: "doc.badge.plus")
            }
            .help("New recipe (⌘N)")
            .fixedSize()
            toolButton("Open…", "folder", "Open a recipe file (⌘O)") { Task { await model.openFileAsking() } }
            toolButton("Save", "square.and.arrow.down", "Save (⌘S); Save As is ⇧⌘S") { Task { await model.save() } }
                .disabled(model.library == nil)
            Divider().frame(height: 18)
            toolButton("Undo", "arrow.uturn.backward", "Undo (⌘Z)") { model.undo() }
                .disabled(!model.canUndo)
            toolButton("Redo", "arrow.uturn.forward", "Redo (⇧⌘Z or ⌘Y)") { model.redo() }
                .disabled(!model.canRedo)
            Divider().frame(height: 18)
            RecipeAddStepMenu(model: model, title: "Add Step") { model.addStep($0) }
                .help("Select a step or an arrow first: the new step goes right after it, or into the arrow.")
            Spacer()
            toolButton("Test Run", "play.fill", "Execute capture recipe in Greenshot (⌘R)") { Task { await model.testRun() } }
                .disabled(model.environment.runtime() == nil)
            toolButton("Recipe Manager…", "list.bullet.rectangle", "Open the recipe manager (⇧⌘M)") {
                RecipeManagerService.show(selecting: model.recipe?.id)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func toolButton(_ title: String, _ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .help(help)
    }
}

/// The recipes and automatic steps of the library (upstream's recipe list `AvailableRecipes`).
private struct RecipePickerMenu: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        let library = model.library
        let recipes = library?.recipes ?? []
        let extensions = library?.extensions ?? []
        Menu {
            if recipes.isEmpty && extensions.isEmpty {
                Text("No recipes loaded")
            }
            ForEach(recipes, id: \.recipe.id) { loaded in
                Button(title(of: loaded)) { Task { await model.switchTo(recipeId: loaded.recipe.id) } }
            }
            if !extensions.isEmpty {
                Divider()
                Text("Automatic Steps")
                ForEach(extensions, id: \.recipe.id) { loaded in
                    Button(title(of: loaded)) { Task { await model.switchTo(recipeId: loaded.recipe.id) } }
                }
            }
        } label: {
            Label(model.recipe?.name ?? "Recipes", systemImage: model.isExtension ? "puzzlepiece.extension" : "list.bullet")
        }
        .frame(maxWidth: 260)
        .fixedSize(horizontal: true, vertical: false)
        .help("The recipe to edit")
        .id(model.libraryRevision)
    }

    private func title(of loaded: LoadedRecipe) -> String {
        var text = loaded.recipe.name
        if loaded.isBuiltIn { text += " (built-in)" }
        if !loaded.isEnabled { text += " (Deactivated)" }
        return text
    }
}

/// "Add Step" grouped like upstream's step toolbox (RecipeEditorWindow.xaml:741-854).
struct RecipeAddStepMenu: View {
    @ObservedObject var model: RecipeEditorModel
    var title: String
    var add: (String) -> Void

    var body: some View {
        Menu {
            ForEach(RecipeEditorCatalog.toolbox, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.stepType) { item in
                        Button {
                            add(item.stepType)
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                        }
                        .disabled(!model.environment.hasExecutor(item.stepType))
                    }
                }
            }
        } label: {
            Label(title, systemImage: "plus.square.on.square")
        }
        .fixedSize()
    }
}

// MARK: Header and pending bar

/// The active recipe: name, "(Deactivated)" (click switches), Unload / Reset to Default (upstream xaml:658-679).
private struct RecipeEditorHeader: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        let loaded = model.recipe.flatMap { model.library?.recipe(id: $0.id) }
        HStack(spacing: 10) {
            Image(systemName: model.isExtension ? "puzzlepiece.extension" : "wand.and.rays")
                .foregroundStyle(.secondary)
            Text(model.recipe?.name ?? "No recipe")
                .font(.headline)
            if let loaded, !model.isExtension {
                Button(loaded.isEnabled ? "Active" : "(Deactivated)") { model.toggleActive() }
                    .buttonStyle(.link)
                    .help(loaded.isEnabled ? "Click to deactivate the recipe" : "Click to activate the recipe")
            } else if model.recipe != nil {
                Text(model.fileURL == nil ? "Not saved yet" : "Not loaded in Greenshot")
                    .foregroundStyle(.secondary)
            }
            if model.isDirty {
                Text("Unsaved changes").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            if let loaded, !loaded.isBuiltIn {
                Button(loaded.replacesBuiltIn ? "Reset to Default" : "Unload") { Task { await model.unloadAsking() } }
                    .help(loaded.replacesBuiltIn ? "Bring back the built-in recipe this file replaces" : "Remove the recipe from Greenshot")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .id(model.libraryRevision)
    }
}

/// What saving will ask for, or what is pending for the file's approval (upstream xaml:645-680).
private struct RecipePendingBar: View {
    @ObservedObject var model: RecipeEditorModel
    let notice: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
            Text(notice)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if model.canReviewApproval {
                Button("Review approval…") { Task { await model.reviewApproval() } }
                    .help("Switch the recipe's triggers and permissions")
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.yellow.opacity(0.18))
    }
}

private struct RecipeEditorEmptyState: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 12) {
            Text("No recipe open").font(.title3)
            HStack {
                Button("New Recipe") { model.newRecipe() }
                Button("Open…") { Task { await model.openFileAsking() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Sides

private struct RecipeEditorSidebar: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 0) {
            RecipeOutlineView(model: model)
            Divider()
            RecipeIssuesView(model: model)
        }
    }
}

/// The tabs: Step, Recipe, Triggers, Options, Error Routes, JSON, Flow.
private struct RecipeEditorDetail: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                ForEach(RecipeEditorModel.Tab.allCases) { tab in
                    Text(label(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            content
        }
    }

    private func label(_ tab: RecipeEditorModel.Tab) -> String {
        switch tab {
        case .triggers: return model.isExtension ? "Triggers" : "Triggers (\(model.recipe?.triggers.count ?? 0))"
        case .options: return "Options (\(model.recipe?.options?.count ?? 0))"
        default: return tab.rawValue
        }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .step: RecipeStepInspector(model: model)
        case .recipe: RecipeInfoTab(model: model)
        case .triggers: RecipeTriggersTab(model: model)
        case .options: RecipeOptionsTab(model: model)
        case .errors: RecipeErrorRoutesTab(model: model)
        case .json: RecipeJSONTab(model: model)
        case .flow: RecipeFlowTab(model: model)
        }
    }
}

/// Validation errors and warnings; a click selects the step (RCP-303).
private struct RecipeIssuesView: View {
    @ObservedObject var model: RecipeEditorModel
    @State private var expanded = true

    var body: some View {
        let errors = model.diagnostics.filter(\.isError).count
        let warnings = model.diagnostics.count - errors
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                    Image(systemName: errors > 0 ? "xmark.octagon.fill" : warnings > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(errors > 0 ? Color.red : warnings > 0 ? Color.orange : Color.green)
                    Text(summary(errors: errors, warnings: warnings)).font(.callout)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if expanded && !model.diagnostics.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.diagnostics) { diagnostic in
                            RecipeIssueRow(model: model, diagnostic: diagnostic)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(10)
    }

    private func summary(errors: Int, warnings: Int) -> String {
        if errors == 0 && warnings == 0 { return "No problems" }
        let e = errors == 1 ? "1 error" : "\(errors) errors"
        let w = warnings == 1 ? "1 warning" : "\(warnings) warnings"
        if errors == 0 { return w }
        return warnings == 0 ? e : "\(e), \(w)"
    }
}

private struct RecipeIssueRow: View {
    @ObservedObject var model: RecipeEditorModel
    let diagnostic: RecipeDiagnostic

    var body: some View {
        Button {
            switch diagnostic.target {
            case .node(let id): model.select(nodeId: id)
            case .trigger: model.tab = .triggers
            case .option: model.tab = .options
            case .errorRoutes: model.tab = .errors
            case .recipe: model.tab = .recipe
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: diagnostic.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diagnostic.isError ? Color.red : Color.orange)
                    .font(.caption)
                Text(diagnostic.message)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeEditorStatusLine: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        HStack {
            Text(model.status.isEmpty ? " " : model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let url = model.fileURL {
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

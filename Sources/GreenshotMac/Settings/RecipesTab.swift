// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import GreenshotCore
import SwiftUI

/// Settings › Recipes (RCP-002, APP-095): the recipe switch (upstream `EnableRecipeFeature`, in the RecipeEditor plug-in's
/// settings there), the recipes with their files and approvals, Import and Reload (RUI), then the option sections of the
/// automatic steps and recipes (RMANAGER's `RecipeOptionsSections`).
struct RecipesSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model: RecipeSettingsModel

    init(store: SettingsStore, model: RecipeSettingsModel? = nil) {
        self.store = store
        _model = StateObject(wrappedValue: model ?? RecipeSettingsModel())
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use recipes", isOn: store.binding(\.recipes.enabled))
                    .managed(\.recipes.enabled)
                Text("Recipes run a capture as a series of steps, started by a hotkey, a menu entry, the clipboard, Open With or the command line. A recipe file is only used after you approved what it does.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Recipes")
            }
            if store.value.recipes.enabled {
                RecipeSettingsList(store: store, model: model)
                if !model.clashes.isEmpty {
                    Section {
                        ForEach(Array(model.clashes.enumerated()), id: \.offset) { _, clash in
                            Label(clash.text, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("Recipe hotkeys not registered")
                    }
                }
            }
            RecipeOptionsSections(store: store)
        }
        .formStyle(.grouped)
    }
}

/// The recipes with their switch and actions, and Import / Reload / the manager and editor.
struct RecipeSettingsList: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var model: RecipeSettingsModel

    var body: some View {
        Section {
            if !model.isRunning {
                Text("The recipes start with Greenshot.").foregroundStyle(.secondary)
            } else if model.rows.isEmpty {
                Text("No recipes yet. Import a recipe file or create one in the recipe editor.").foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                RecipeSettingsRowView(row: row, model: model, filesLocked: store.isLocked(\AppSettings.recipes.files))
            }
        } header: {
            Text("Your recipes")
        } footer: {
            HStack {
                Button("Import Recipe…") { model.importRecipe() }
                    .managed(\.recipes.files)
                Button("Reload Recipes") { model.reload() }
                Spacer()
                Button("Recipe Manager…") { RecipeManagerService.show(selecting: nil) }
                Button("Recipe Editor…") { RecipeEditorService.openEditor(recipeId: nil) }
            }
            .disabled(!model.isRunning)
        }
    }
}

struct RecipeSettingsRowView: View {
    let row: RecipeSettingsRow
    @ObservedObject var model: RecipeSettingsModel
    let filesLocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { row.isEnabled }, set: { model.setEnabled($0, recipeId: row.id) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .managed(\.recipes.disabledRecipeIds)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).fontWeight(.semibold)
                    if row.isBuiltIn { ApprovalBadge(text: String(localized: "BUILT-IN"), tone: .neutral) }
                    if row.replacesBuiltIn { ApprovalBadge(text: String(localized: "REPLACES BUILT-IN"), tone: .accent) }
                    if row.proposedBy != nil { ApprovalBadge(text: String(localized: "AI"), tone: .warning) }
                }
                Text(row.triggers).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(row.source).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let tool = row.proposedBy {
                    Text("Written by an AI tool and approved by you: \(tool)").font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Details…") { model.showDetails(row) }
                if row.fileURL != nil {
                    Button("Permissions…") { model.review(row) }
                    Button("Revoke Approval…") { model.revoke(row) }
                    if row.replacesBuiltIn { Button("Reset Default") { model.resetToDefault(row) } }
                    Button("Unload") { model.unload(row) }.disabled(filesLocked)
                    Divider()
                    Button("Show in Finder") { model.showInFinder(row) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Details, permissions and the file of this recipe")
        }
    }
}

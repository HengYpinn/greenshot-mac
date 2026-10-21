// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The automatic steps' and recipes' option sections at the bottom of Settings › Recipes (RCP-175, RCP-230, RCP-231;
/// upstream `SettingsWindow.xaml` Recipes tab, `SettingsViewModel.RecipeOptions`, `RecipeOptionGroupViewModel`): each
/// automatic step with its on/off checkbox in front of its name, its options only while it is on, "Used for" with
/// "Change…"; the recipes with options; "Changed recipes". Values apply at once, like the other tabs (upstream writes
/// them on OK).
struct RecipeOptionsSections: View {
    @ObservedObject var store: SettingsStore
    /// Nil: the running app's library; snapshots hand their own.
    var library: RecipeLibrary? = nil
    @State private var editingScope: ScopeEditing?

    private var currentLibrary: RecipeLibrary {
        library ?? RecipeRuntime.shared?.library ?? RecipeOptionsFallback.library(store: store)
    }

    var body: some View {
        let library = currentLibrary
        // `store` is observed: a change of the option values or the files draws the sections again.
        let destinations = RecipeExtensionScope.destinationChoices(settings: store.value)
        let groups = library.optionGroups(destinations: destinations)
        Section {
            Text("Automatic steps for your captures, like a border or a caption, and the settings your recipes offer. They are used from the next capture on.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Automatic Steps")
        }
        ForEach(groups) { group in
            RecipeOptionGroupSection(group: group, library: library) { scope in
                let name = RecipeOptionTexts.shown(group.name, ownerId: group.id, in: library)
                editingScope = ScopeEditing(id: group.id, name: name, model: RecipeScopeModel(scope: scope))
            }
        }
        changedRecipes(library)
            .sheet(item: $editingScope) { editing in
                RecipeExtensionScopeSheet(name: editing.name, model: editing.model) { scope in
                    library.setExtensionScope(id: editing.id, exceptRecipes: scope.exceptRecipes, onlyDestinations: scope.onlyDestinations)
                    editingScope = nil
                } cancel: {
                    editingScope = nil
                }
            }
    }

    private func changedRecipes(_ library: RecipeLibrary) -> some View {
        let lines = library.recipeChanges()
        return Section("Changed recipes") {
            if lines.isEmpty {
                Text("No automatic step changes a recipe; switch one on above.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines, id: \.extensions) { line in
                    LabeledContent(line.extensions) {
                        Text(line.recipes)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The scope dialog that is open.
private struct ScopeEditing: Identifiable {
    let id: String
    let name: String
    let model: RecipeScopeModel
}

/// One automatic step or recipe: the header row (checkbox, name, description, Reset to defaults), then its options while
/// it is on, then "Used for".
struct RecipeOptionGroupSection: View {
    let group: RecipeOptionGroup
    let library: RecipeLibrary
    let changeScope: (RecipeExtensionScope) -> Void
    /// Counts "Reset to defaults", which drops half-typed values (also where the stored value doesn't change).
    @State private var resets = 0

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                if let switchOption = group.switchOption {
                    Toggle(isOn: Binding(get: { group.isOn },
                                         set: { library.setOption(.bool($0), key: switchOption.key, ownerId: group.id) })) {
                        title
                    }
                    .toggleStyle(.checkbox)
                    .managed(\.recipes.optionValues)
                } else {
                    title
                }
                Spacer()
                if group.isOn {
                    Button("Reset to defaults") {
                        library.resetOptions(recipeId: group.id)
                        resets += 1
                    }
                        .controlSize(.small)
                        .managed(\.recipes.optionValues)
                }
            }
            if group.isOn {
                let isBuiltIn = RecipeOptionTexts.isBuiltIn(group.id, in: library)
                ForEach(group.items) { item in
                    RecipeOptionRow(item: item, isBuiltIn: isBuiltIn, resets: resets) {
                        library.setOption($0, key: item.option.key, ownerId: group.id)
                    }
                }
                if let scope = group.scope {
                    LabeledContent("Used for:") {
                        HStack {
                            Text(scope.summary)
                            Button("Change…") { changeScope(scope) }
                                .controlSize(.small)
                                .managed(\.recipes.optionValues)
                        }
                    }
                }
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(RecipeOptionTexts.shown(group.name, ownerId: group.id, in: library)).fontWeight(.semibold)
            if let description = group.description, !description.isEmpty {
                Text(RecipeOptionTexts.shown(description, ownerId: group.id, in: library))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One option: a switch takes the whole row; numbers show their range; a choice is a menu; a colour has its swatch and
/// its text (upstream `RecipeOptionViewModel`). Typed values are applied on Return or when the field loses the focus.
struct RecipeOptionRow: View {
    let item: RecipeOptionItem
    /// The option of a built-in automatic step or recipe: its texts are shown in the language of the app.
    var isBuiltIn = false
    /// Changes on "Reset to defaults": the text fields drop what was typed and not applied yet.
    var resets = 0
    let set: (JSONValue) -> Void

    var body: some View {
        row
            .disabled(!item.isEditable)
            .help(shown(item.option.description ?? ""))
            .managed(\.recipes.optionValues)
    }

    @ViewBuilder private var row: some View {
        switch item.option.type {
        case .boolean:
            Toggle(shown(item.label), isOn: Binding(get: { item.value == .bool(true) }, set: { set(.bool($0)) }))
        case .integer, .decimal:
            LabeledContent {
                HStack(spacing: 8) {
                    if let range = item.rangeText {
                        Text(range).foregroundStyle(.secondary)
                    }
                    RecipeDraftField(text: item.text, width: 64, resets: resets) { set(.string($0)) }
                }
            } label: {
                label
            }
        case .enumeration:
            Picker(shown(item.label), selection: Binding(get: { item.value.asString ?? "" }, set: { set(.string($0)) })) {
                ForEach(item.option.choices ?? [], id: \.value) { choice in
                    Text(choice.label.map(shown) ?? choice.value).tag(choice.value)
                }
            }
            .pickerStyle(.menu)
        case .color:
            LabeledContent {
                HStack(spacing: 8) {
                    RecipeDraftField(text: item.text, width: 96, resets: resets) { set(.string($0)) }
                    ColorPicker("", selection: colorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
            } label: {
                label
            }
        default:
            LabeledContent {
                RecipeDraftField(text: item.text, width: nil, resets: resets) { set(.string($0)) }
            } label: {
                label
            }
        }
    }

    /// Greyed with the row while its switch is off (a text label isn't greyed by `disabled` on its own).
    private var label: some View {
        Text(shown(item.label)).foregroundStyle(item.isEditable ? Color.primary : Color.secondary)
    }

    /// A built-in option's English text in the language of the app (`L10nText.display`); a file's text as it is.
    private func shown(_ text: String) -> String {
        isBuiltIn ? L10nText.display(text) : text
    }

    private var colorBinding: Binding<CGColor> {
        Binding(get: {
            let color = RecipeOptionColor.parse(item.text) ?? RGBAColor(red: 0, green: 0, blue: 0)
            return CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }, set: { cgColor in
            guard let srgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
                  let parts = srgb.components, parts.count >= 3 else { return }
            let alpha = parts.count > 3 ? Double(parts[3]) : 1
            set(.string(RecipeOptionColor.format(RGBAColor(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]), alpha: alpha))))
        })
    }
}

/// A text field that hands its text over on Return or when it loses the focus (upstream `UpdateSourceTrigger=LostFocus`),
/// so half-typed numbers and colours aren't clamped or refused while typing. A new value from elsewhere (Reset to
/// defaults, the colour well, another window) or a reset drops the typed text, which would else be applied afterwards.
struct RecipeDraftField: View {
    let text: String
    let width: CGFloat?
    var resets = 0
    let commit: (String) -> Void
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: Binding(get: { draft ?? text }, set: { draft = $0 }))
            .labelsHidden()
            .multilineTextAlignment(width == nil ? .leading : .trailing)
            .frame(width: width)
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { apply() }
            }
            .onChange(of: text) { _, _ in draft = nil }
            .onChange(of: resets) { _, _ in draft = nil }
    }

    private func apply() {
        guard let value = draft else { return }
        draft = nil
        if value != text { commit(value) }
    }
}

/// The texts of a recipe's or automatic step's options (Settings › Recipes, Quick Settings): a built-in one's name,
/// description and option texts are English data, shown in the language of the app where upstream has the text
/// (`L10nText.display`, upstream `[Recipe] extension_*`); a file's texts are shown as they are.
@MainActor
enum RecipeOptionTexts {
    static func isBuiltIn(_ ownerId: String, in library: RecipeLibrary) -> Bool {
        (library.loadedExtension(id: ownerId) ?? library.recipe(id: ownerId))?.isBuiltIn == true
    }

    static func shown(_ text: String, ownerId: String, in library: RecipeLibrary) -> String {
        isBuiltIn(ownerId, in: library) ? L10nText.display(text) : text
    }
}

/// Settings › Recipes before the recipes started (the window opened very early) and in `--snapshot`: the built-in
/// automatic steps on the same settings, without files or approvals.
@MainActor
enum RecipeOptionsFallback {
    private static var cached: (store: ObjectIdentifier, library: RecipeLibrary)?

    static func library(store: SettingsStore) -> RecipeLibrary {
        if let cached, cached.store == ObjectIdentifier(store) { return cached.library }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-recipe-options", isDirectory: true)
        let library = RecipeLibrary(loadSettings: { store.value.recipes }, saveSettings: { recipes in store.update { $0.recipes = recipes } },
                                    trustStore: RecipeTrustStore(fileURL: folder.appendingPathComponent("unused.json"), secrets: InMemorySecretStore()),
                                    approver: nil, watchFiles: false)
        cached = (ObjectIdentifier(store), library)
        return library
    }
}

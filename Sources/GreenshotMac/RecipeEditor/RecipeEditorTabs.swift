// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

// MARK: Recipe

/// Recipe ID (with Copy), Name, Description, Version (upstream xaml:3139-3168); an automatic step's place in the recipes
/// (upstream xaml:3177-3200: recipes, slot, order, when).
struct RecipeInfoTab: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.isExtension ? "AUTOMATIC STEP" : "RECIPE CONFIGURATION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                RecipeDiagnosticList(diagnostics: model.diagnostics(for: .recipe))
                RecipeLabeled(model.isExtension ? "Automatic Step ID" : "Recipe ID") {
                    HStack {
                        TextField("id", text: text(\.id)).textFieldStyle(.roundedBorder)
                        Button("Copy") { model.copyRecipeId() }.help("Copy Recipe ID to Clipboard")
                    }
                }
                RecipeLabeled("Name") { TextField("name", text: text(\.name)).textFieldStyle(.roundedBorder) }
                RecipeLabeled("Description") {
                    TextField("what it does", text: optionalText(\.description), axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
                }
                RecipeLabeled("Version") { TextField("1.0", text: text(\.version)).textFieldStyle(.roundedBorder).frame(width: 100) }
                if model.isExtension {
                    RecipeExtensionTarget(model: model)
                } else {
                    RecipeLabeled("When it runs again") {
                        Picker("", selection: Binding(get: { model.recipe?.concurrency?.rawValue ?? "" },
                                                      set: { raw in model.edit { $0.concurrency = FlowConcurrency(rawValue: raw) } })) {
                            Text("Default (in parallel)").tag("")
                            Text("In parallel").tag(FlowConcurrency.parallel.rawValue)
                            Text("Once at a time").tag(FlowConcurrency.exclusive.rawValue)
                            Text("Cancel the running one").tag(FlowConcurrency.replacePrevious.rawValue)
                        }
                        .labelsHidden().frame(width: 220)
                    }
                    RecipeLabeled("Menus") {
                        Toggle("Show in the Recipes menu", isOn: Binding(get: { model.recipe?.showInContextMenu ?? true },
                                                                         set: { on in model.edit { $0.showInContextMenu = on } }))
                    }
                }
                Divider()
                Text("Start steps run first; several start steps run at the same time (upstream START STEPS). Mark them in the step list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func text(_ keyPath: WritableKeyPath<CaptureRecipe, String>) -> Binding<String> {
        Binding(get: { model.recipe?[keyPath: keyPath] ?? "" }, set: { value in model.edit { $0[keyPath: keyPath] = value } })
    }

    private func optionalText(_ keyPath: WritableKeyPath<CaptureRecipe, String?>) -> Binding<String> {
        Binding(get: { model.recipe?[keyPath: keyPath] ?? "" }, set: { value in model.edit { $0[keyPath: keyPath] = value.isEmpty ? nil : value } })
    }
}

private struct RecipeExtensionTarget: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        let target = model.recipe?.extends ?? ExtensionTarget()
        VStack(alignment: .leading, spacing: 10) {
            Text("Greenshot adds these steps to other recipes: put them before Out in the step list, switch the automatic step on in Settings › Recipes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            RecipeLabeled("Recipes") {
                TextField("ids, * or *capture", text: Binding(get: { target.recipes.joined(separator: ", ") }, set: { text in
                    let ids = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    model.edit { recipe in
                        var changed = recipe.extends ?? ExtensionTarget()
                        changed.recipes = ids
                        recipe.extends = changed
                    }
                }))
                .textFieldStyle(.roundedBorder)
                .help("Recipes: ids, * (every recipe with the slot) or *capture, separated by commas")
            }
            RecipeLabeled("Slot") {
                Picker("", selection: Binding(get: { target.slot ?? "" }, set: { slot in
                    model.edit { recipe in
                        var changed = recipe.extends ?? ExtensionTarget()
                        changed.slot = slot
                        recipe.extends = changed
                    }
                })) {
                    ForEach(RecipeEditorCatalog.slotNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
            RecipeLabeled("Order") {
                TextField("0", value: Binding(get: { target.order }, set: { order in
                    model.edit { recipe in
                        var changed = recipe.extends ?? ExtensionTarget()
                        changed.order = order
                        recipe.extends = changed
                    }
                }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 100)
                .help("Several on one slot run by order, then by id")
            }
            RecipeLabeled("When") {
                TextField("${payload.width > 800}", text: Binding(get: { model.recipe?.when ?? "" }, set: { text in
                    model.edit { $0.when = text.isEmpty ? nil : text }
                }))
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
        }
    }
}

// MARK: Triggers

/// The triggers (upstream xaml:3311-3480): add by type, each with its switch, name, delete and the fields of its type.
struct RecipeTriggersTab: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        if model.isExtension {
            Text("An automatic step has no triggers: it runs in the recipes it extends.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("TRIGGERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Menu("+ Add Trigger") {
                            ForEach(RecipeEditorCatalog.triggerTypes, id: \.type) { entry in
                                Button(entry.title) { addTrigger(entry.type) }
                            }
                        }
                        .fixedSize()
                    }
                    Text("Any trigger can run the recipe; each has its own switch. Triggers that start the recipe on their own or from outside are approved separately.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    let triggers = model.recipe?.triggers ?? []
                    if triggers.isEmpty {
                        Text("No triggers: the recipe starts only from the recipe manager, a test run or another recipe.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(triggers.indices), id: \.self) { index in
                        RecipeTriggerBox(model: model, index: index)
                    }
                }
                .padding(16)
            }
        }
    }

    private func addTrigger(_ type: String) {
        guard let recipe = model.recipe else { return }
        let trigger = RecipeEditorCatalog.newTrigger(type, for: recipe)
        model.edit("Added \(type) trigger") { $0.triggers.append(trigger) }
    }
}

private struct RecipeTriggerBox: View {
    @ObservedObject var model: RecipeEditorModel
    let index: Int

    var body: some View {
        let trigger = model.recipe.flatMap { $0.triggers.indices.contains(index) ? $0.triggers[index] : nil }
        let contract = trigger.flatMap { TriggerContractCatalog.builtIn.contract(for: $0.triggerType) }
        if let trigger {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("", isOn: Binding(get: { trigger.enabled }, set: { on in edit { $0.enabled = on } }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Text(contract?.displayName ?? trigger.triggerType).font(.headline)
                        TextField("Trigger Name", text: Binding(get: { trigger.name ?? "" }, set: { text in edit { $0.name = text.isEmpty ? nil : text } }))
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            model.edit("Trigger removed") { recipe in
                                if recipe.triggers.indices.contains(index) { recipe.triggers.remove(at: index) }
                            }
                        } label: { Image(systemName: "trash") }
                        .help("Delete Trigger")
                    }
                    if let description = contract?.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                    RecipeDiagnosticList(diagnostics: model.diagnostics(for: .trigger(index)))
                    ForEach(contract.map(RecipeParameterForm.fields(for:)) ?? []) { field in
                        RecipeFieldRow(field: field, value: parameter(field.name))
                    }
                    if contract == nil {
                        RecipeFieldRow(field: RecipeEditorField(name: "parameters", label: "Parameters", kind: .json),
                                       value: Binding(get: { .object(trigger.parameters) },
                                                      set: { value in edit { $0.parameters = value?.objectValue ?? [:] } }))
                    }
                }
                .padding(6)
            }
        }
    }

    private func edit(_ change: @escaping (inout TriggerConfig) -> Void) {
        model.edit { recipe in
            guard recipe.triggers.indices.contains(index) else { return }
            change(&recipe.triggers[index])
        }
    }

    private func parameter(_ name: String) -> Binding<JSONValue?> {
        Binding(get: { model.recipe.flatMap { $0.triggers.indices.contains(index) ? $0.triggers[index].parameters[name] : nil } },
                set: { value in edit { $0.parameters[name] = value } })
    }
}

// MARK: Options

/// Declared options (upstream RecipeEditorViewModel.Options.cs, xaml:3203-3280): key, type, label, default, range,
/// choices, quick settings, "only when", template.
struct RecipeOptionsTab: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("OPTIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("+ Option") { add() }
                }
                Text("Values the user sets in Settings › Recipes; steps read them as ${option.key}.")
                    .font(.caption).foregroundStyle(.secondary)
                let options = model.recipe?.options ?? []
                ForEach(Array(options.indices), id: \.self) { index in
                    RecipeOptionBox(model: model, index: index)
                }
            }
            .padding(16)
        }
    }

    private func add() {
        guard let recipe = model.recipe else { return }
        let option = RecipeEditorCatalog.newOption(for: recipe)
        model.edit("Added option '\(option.key)': the steps read it with ${option.\(option.key)}") { recipe in
            recipe.options = (recipe.options ?? []) + [option]
        }
    }
}

private struct RecipeOptionBox: View {
    @ObservedObject var model: RecipeEditorModel
    let index: Int

    var body: some View {
        let options = model.recipe?.options ?? []
        if options.indices.contains(index) {
            let option = options[index]
            let booleans = options.filter { $0.type == .boolean && $0.key != option.key }.map(\.key)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("key", text: Binding(get: { option.key }, set: { key in edit { $0.key = key.trimmingCharacters(in: .whitespaces) } }))
                            .textFieldStyle(.roundedBorder).frame(width: 160)
                        Picker("", selection: Binding(get: { option.type }, set: { type in edit { $0.type = type } })) {
                            ForEach([ContractDataType.boolean, .integer, .decimal, .string, .enumeration, .color], id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .labelsHidden().frame(width: 110)
                        Text("${option.\(option.key)}").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }.help("Remove the option")
                    }
                    RecipeDiagnosticList(diagnostics: model.diagnostics(for: .option(option.key)))
                    RecipeLabeled("Label") { textField("Label", \.label) }
                    RecipeLabeled("Description") { textField("Description", \.description) }
                    RecipeFieldRow(field: RecipeEditorField(name: "default", label: "Default", kind: defaultKind(option)),
                                   value: Binding(get: { option.defaultValue }, set: { value in edit { $0.defaultValue = value } }))
                    if option.type == .integer || option.type == .decimal {
                        RecipeLabeled("Range") {
                            HStack {
                                numberField("Smallest value", \.min)
                                Text("to")
                                numberField("Largest value", \.max)
                            }
                        }
                    }
                    if option.type == .enumeration {
                        RecipeLabeled("Choices") {
                            TextField("One per line: value, or value = label", text: choicesText(option), axis: .vertical)
                                .lineLimit(2...8).textFieldStyle(.roundedBorder)
                        }
                    }
                    if option.type == .string {
                        RecipeLabeled("Template") {
                            Toggle("The value is a template (${…} work in it)", isOn: Binding(
                                get: { option.isTemplate }, set: { on in edit { $0.format = on ? RecipeOption.formatTemplate : nil } }))
                        }
                    }
                    RecipeLabeled("Quick settings") {
                        Toggle("Show in the menu bar's Quick Settings", isOn: Binding(get: { option.quickSettings },
                                                                                       set: { on in edit { $0.quickSettings = on } }))
                            .disabled(option.type != .boolean && option.type != .enumeration)
                    }
                    RecipeLabeled("Only when") {
                        Picker("", selection: Binding(get: { option.enabledWhen ?? "" },
                                                      set: { key in edit { $0.enabledWhen = key.isEmpty ? nil : key } })) {
                            Text("Always").tag("")
                            ForEach(booleans, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 200)
                        .help("The key of a Boolean option: this option can only be changed while that one is on")
                    }
                }
                .padding(6)
            }
        }
    }

    private func defaultKind(_ option: RecipeOption) -> RecipeEditorFieldKind {
        switch option.type {
        case .boolean: return .boolean
        case .integer: return .integer
        case .decimal: return .decimal
        case .color: return .color
        case .enumeration: return .choice(option.choices?.map(\.value) ?? [])
        default: return .text
        }
    }

    private func edit(_ change: @escaping (inout RecipeOption) -> Void) {
        model.edit { recipe in
            guard var options = recipe.options, options.indices.contains(index) else { return }
            change(&options[index])
            recipe.options = options
        }
    }

    private func remove() {
        model.edit("Removed an option") { recipe in
            guard var options = recipe.options, options.indices.contains(index) else { return }
            options.remove(at: index)
            recipe.options = options.isEmpty ? nil : options
        }
    }

    private func textField(_ placeholder: String, _ keyPath: WritableKeyPath<RecipeOption, String?>) -> some View {
        let options = model.recipe?.options ?? []
        let current = options.indices.contains(index) ? options[index][keyPath: keyPath] : nil
        return TextField(placeholder, text: Binding(get: { current ?? "" },
                                                    set: { text in edit { $0[keyPath: keyPath] = text.isEmpty ? nil : text } }))
            .textFieldStyle(.roundedBorder)
    }

    private func numberField(_ placeholder: String, _ keyPath: WritableKeyPath<RecipeOption, Double?>) -> some View {
        let options = model.recipe?.options ?? []
        let current = options.indices.contains(index) ? options[index][keyPath: keyPath] : nil
        return TextField(placeholder, text: Binding(get: { current.map { JSONValue.number($0).interpolationText } ?? "" },
                                                    set: { text in edit { $0[keyPath: keyPath] = Double(text.trimmingCharacters(in: .whitespaces)) } }))
            .textFieldStyle(.roundedBorder).frame(width: 110)
    }

    private func choicesText(_ option: RecipeOption) -> Binding<String> {
        Binding(get: {
            (option.choices ?? []).map { choice in choice.label.map { "\(choice.value) = \($0)" } ?? choice.value }.joined(separator: "\n")
        }, set: { text in
            let choices = text.components(separatedBy: "\n").compactMap { line -> RecipeOptionChoice? in
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let value = parts.first, !value.isEmpty else { return nil }
                return RecipeOptionChoice(value: value, label: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
            }
            edit { $0.choices = choices.isEmpty ? nil : choices }
        })
    }
}

// MARK: Error routes

/// "ERROR HANDLING & FALLBACK" (upstream xaml:3497-3530): routes from a step or any step (*) for an error type to a
/// step of the recipe or another recipe.
struct RecipeErrorRoutesTab: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ERROR HANDLING & FALLBACK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("+ Add Error Fallback Route") { add() }
                }
                Text("Define what should happen when a step fails (e.g. clipboard lock, network timeout). Route the capture to a fallback step or another recipe.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                RecipeDiagnosticList(diagnostics: model.diagnostics(for: .errorRoutes))
                let routes = model.recipe?.flow.errorTransitions ?? []
                ForEach(Array(routes.indices), id: \.self) { index in
                    RecipeErrorRouteBox(model: model, index: index)
                }
            }
            .padding(16)
        }
    }

    private func add() {
        guard let recipe = model.recipe else { return }
        let route = RecipeEditorCatalog.newErrorTransition(for: recipe)
        model.edit("Added recipe error fallback route") { $0.flow.errorTransitions.append(route) }
    }
}

private struct RecipeErrorRouteBox: View {
    @ObservedObject var model: RecipeEditorModel
    let index: Int

    var body: some View {
        let routes = model.recipe?.flow.errorTransitions ?? []
        if routes.indices.contains(index) {
            let route = routes[index]
            let toRecipe = route.targetRecipeId != nil
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    RecipeLabeled("From") {
                        HStack {
                            RecipeNodePicker(model: model, selection: Binding(get: { route.from ?? "*" }, set: { id in edit { $0.from = id } }),
                                             allowAny: true)
                            Spacer()
                            Button(role: .destructive) {
                                model.edit("Removed recipe error fallback route") { recipe in
                                    if recipe.flow.errorTransitions.indices.contains(index) { recipe.flow.errorTransitions.remove(at: index) }
                                }
                            } label: { Image(systemName: "trash") }
                            .help("Remove this error route")
                        }
                    }
                    RecipeLabeled("Error Filter") {
                        TextField("* = all errors", text: Binding(get: { route.errorType }, set: { text in edit { $0.errorType = text.isEmpty ? "*" : text } }))
                            .textFieldStyle(.roundedBorder).frame(width: 220)
                    }
                    RecipeLabeled("Route To") {
                        Picker("", selection: Binding(get: { toRecipe }, set: { recipe in
                            edit { route in
                                if recipe {
                                    route.to = nil
                                    route.targetRecipeId = route.targetRecipeId ?? ""
                                } else {
                                    route.targetRecipeId = nil
                                    route.to = route.to ?? model.recipe?.nodes.first?.id
                                }
                            }
                        })) {
                            Text("Step in this Recipe").tag(false)
                            Text("Another Recipe").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                    }
                    RecipeLabeled(toRecipe ? "Recipe" : "Step") {
                        if toRecipe {
                            RecipeRecipePicker(model: model, selection: Binding(get: { route.targetRecipeId ?? "" },
                                                                                set: { id in edit { $0.targetRecipeId = id } }))
                        } else {
                            RecipeNodePicker(model: model, selection: Binding(get: { route.to ?? "" }, set: { id in edit { $0.to = id } }))
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    private func edit(_ change: @escaping (inout ErrorTransition) -> Void) {
        model.edit { recipe in
            guard recipe.flow.errorTransitions.indices.contains(index) else { return }
            change(&recipe.flow.errorTransitions[index])
        }
    }
}

// MARK: JSON

/// The recipe as JSON, editable; "Apply Changes" reads it back (upstream xaml:939-947, `ApplyJson`). Unapplied text is
/// kept as the model's draft (switching tabs doesn't lose it, Save and closing ask about it); without a draft the text
/// follows the recipe (undo, the forms).
struct RecipeJSONTab: View {
    @ObservedObject var model: RecipeEditorModel
    @State private var problem: String?

    var body: some View {
        let text = Binding<String>(get: { model.jsonDraft ?? model.content ?? "" }, set: { model.setJSONDraft($0) })
        VStack(alignment: .leading, spacing: 8) {
            if model.jsonDraftIsStale {
                Label("The recipe changed after you started editing the JSON: Apply replaces those changes, Revert shows the recipe as it is.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.3))
            HStack {
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red).lineLimit(3)
                } else if model.jsonDraft != nil {
                    Text("Changes not applied yet").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Revert") {
                    model.discardJSONDraft()
                    problem = nil
                }
                .disabled(model.jsonDraft == nil)
                Button("Apply Changes") { problem = model.applyJSON(model.jsonDraft ?? model.content ?? "") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.jsonDraft == nil)
            }
        }
        .padding(12)
    }
}

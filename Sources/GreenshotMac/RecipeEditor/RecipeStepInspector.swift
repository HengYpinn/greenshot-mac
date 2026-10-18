// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension RecipeEditorModel {
    /// A step parameter as a binding (nil: not in the recipe, the default applies).
    func parameterBinding(_ nodeId: String, _ name: String) -> Binding<JSONValue?> {
        Binding(get: { [weak self] in self?.recipe?.node(nodeId)?.parameters[name] },
                set: { [weak self] newValue in self?.editNode(nodeId) { RecipeParameterForm.set(newValue, for: name, in: &$0.parameters) } })
    }
}

/// The Step tab (upstream "Step Inspector", RecipeEditorWindow.xaml:992-1125): id (renaming updates every reference),
/// type, name, enabled, start step, the form generated from the step's contract, other parameters, and "On Error".
struct RecipeStepInspector: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        if let node = model.selectedNode {
            ScrollView {
                RecipeNodeForm(model: model, nodeId: node.id)
                    .padding(16)
                    .id(node.id)
            }
        } else {
            RecipeNoSelection(model: model)
        }
    }
}

private struct RecipeNoSelection: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 8) {
            Text("No Step Selected").font(.title3)
            Text("Select a step in the list to change it, or add one with Add Step: it goes after the selected step, into the selected branch, lane or arrow.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecipeNodeForm: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String

    var body: some View {
        let node = model.recipe?.node(nodeId)
        let contract = node.flatMap { model.contracts.contract(for: $0.stepType) }
        VStack(alignment: .leading, spacing: 14) {
            RecipeNodeHeader(model: model, nodeId: nodeId, contract: contract)
            RecipeDiagnosticList(diagnostics: model.diagnostics(for: .node(nodeId)))
            if let node, let contract {
                RecipeParameterSection(model: model, node: node, contract: contract)
            } else if let node {
                Text("Greenshot for Mac has no step '\(node.stepType)': its parameters are kept as they are.")
                    .foregroundStyle(.secondary)
            }
            if let node, node.stepType.caseInsensitiveCompare(WellKnownStepType.slot) == .orderedSame {
                RecipeSlotPlugins(model: model, node: node)
            }
            if let node {
                RecipeOtherParameters(model: model, node: node, contract: contract)
                RecipeOnErrorSection(model: model, node: node)
            }
        }
    }
}

/// Node ID, Step Type, Display Name, Enabled, start step, delete (upstream xaml:1040-1082).
private struct RecipeNodeHeader: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String
    let contract: StepContract?
    @State private var idText = ""
    @FocusState private var idFocused: Bool

    var body: some View {
        let node = model.recipe?.node(nodeId)
        let isStart = model.recipe.map { RecipeFlowEditor.isStart(nodeId, in: $0) } ?? false
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: RecipeEditorCatalog.symbol(for: node?.stepType ?? ""))
                Text(contract?.displayName ?? node?.stepType ?? "").font(.title3.weight(.semibold))
                Text(node?.stepType ?? "").foregroundStyle(.secondary)
                Spacer()
                Button(isStart ? "Remove Start Step" : "Mark as Start Step") { model.toggleStart(nodeId) }
                    .help(isStart ? "Remove this step from the start steps" : "Add this step as a parallel entry point")
                Button(role: .destructive) { model.deleteStep(nodeId) } label: { Label("Delete Step", systemImage: "trash") }
            }
            if let description = contract?.description, !description.isEmpty {
                Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            RecipeLabeled(String(localized: "Node ID")) {
                TextField("id", text: $idText)
                    .textFieldStyle(.roundedBorder)
                    .focused($idFocused)
                    .onSubmit { commitId() }
                    .help("Unique identifier for this step. Editing this ID updates all references.")
            }
            RecipeLabeled(String(localized: "Display Name")) {
                TextField(contract?.displayName ?? String(localized: "name"), text: Binding(
                    get: { node?.name ?? "" },
                    set: { text in model.editNode(nodeId) { $0.name = text.isEmpty ? nil : text } }))
                    .textFieldStyle(.roundedBorder)
            }
            RecipeLabeled(String(localized: "Runs")) {
                RecipeEnabledControl(model: model, nodeId: nodeId)
            }
        }
        .onAppear { idText = node?.id ?? nodeId }
        .onChange(of: idFocused) { _, focused in if !focused { commitId() } }
    }

    private func commitId() {
        let trimmed = idText.trimmingCharacters(in: .whitespaces)
        guard trimmed != nodeId else { return }
        model.rename(nodeId, to: trimmed)
        if model.recipe?.node(trimmed) == nil { idText = nodeId }
    }
}

/// `enabled`: always, never, or when an expression like `${option.border}` is true (RCP-154).
private struct RecipeEnabledControl: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String

    var body: some View {
        let enabled = model.recipe?.node(nodeId)?.enabled ?? .value(true)
        let mode = Binding<String>(get: {
            switch enabled {
            case .value(true): return "always"
            case .value(false): return "never"
            case .expression: return "when"
            }
        }, set: { choice in
            model.editNode(nodeId) { node in
                switch choice {
                case "never": node.enabled = .value(false)
                case "when": node.enabled = .expression("${option.enabled}")
                default: node.enabled = .value(true)
                }
            }
        })
        HStack {
            Picker("", selection: mode) {
                Text("Always").tag("always")
                Text("Never (switched off)").tag("never")
                Text("When…").tag("when")
            }
            .labelsHidden()
            .frame(width: 190)
            if case .expression(let expression) = enabled {
                TextField("${option.key}", text: Binding(get: { expression },
                                                         set: { text in model.editNode(nodeId) { $0.enabled = .expression(text) } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}

/// "STEP PARAMETERS": the generated form; fields of other effects / source types / destinations are hidden unless
/// "Show all parameters" is on.
private struct RecipeParameterSection: View {
    @ObservedObject var model: RecipeEditorModel
    let node: RecipeNode
    let contract: StepContract

    var body: some View {
        let isAnnotation = contract.stepType.caseInsensitiveCompare(WellKnownStepType.annotation) == .orderedSame
        // The Annotation step's single-annotation `Type` is edited in the annotations list.
        let fields = RecipeParameterForm.fields(for: contract).filter { !isAnnotation || $0.name != "Type" }
        let shown = fields.filter { model.showAllParameters || RecipeParameterForm.isVisible($0, in: node, contract: contract) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STEP PARAMETERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Show all parameters", isOn: $model.showAllParameters).controlSize(.small)
            }
            if fields.isEmpty { Text("This step has no parameters.").foregroundStyle(.secondary) }
            ForEach(shown) { field in
                if field.kind == .annotations {
                    RecipeAnnotationsEditor(model: model, nodeId: node.id)
                } else {
                    RecipeFieldRow(field: field, value: model.parameterBinding(node.id, field.name),
                                   externalCommands: model.environment.externalCommandNames())
                }
            }
            if shown.count < fields.count {
                Text("\(fields.count - shown.count) more parameters apply to other choices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Parameters the contract doesn't name (kept as they are, upstream keeps them too).
private struct RecipeOtherParameters: View {
    @ObservedObject var model: RecipeEditorModel
    let node: RecipeNode
    let contract: StepContract?

    var body: some View {
        let keys = contract?.acceptsUndeclaredParameters == true && contract?.stepType.caseInsensitiveCompare(WellKnownStepType.annotation) == .orderedSame
            ? node.parameters.keys.filter { contract?.parameter($0) == nil && !RecipeAnnotationSchema.knownKeys.contains($0.lowercased()) }
            : RecipeParameterForm.undeclaredKeys(of: node, contract: contract)
        if !keys.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("OTHER PARAMETERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(keys, id: \.self) { key in
                    RecipeFieldRow(field: RecipeEditorField(name: key, label: key, help: String(localized: "Not a parameter of this step"), kind: .json),
                                   value: model.parameterBinding(node.id, key))
                }
            }
        }
    }
}

/// The automatic steps that plug into a slot now (upstream `GetSlotExtensions`: greyed, "(off)" when switched off).
private struct RecipeSlotPlugins: View {
    @ObservedObject var model: RecipeEditorModel
    let node: RecipeNode

    var body: some View {
        let plugged = model.recipe.flatMap { recipe in model.library?.extensionsPlugging(into: node, of: recipe) } ?? []
        VStack(alignment: .leading, spacing: 4) {
            Text("Automatic steps which plug in now (switched in Settings › Recipes):")
                .font(.caption).foregroundStyle(.secondary)
            if plugged.isEmpty {
                Text("None").foregroundStyle(.tertiary)
            }
            ForEach(Array(plugged.enumerated()), id: \.offset) { _, item in
                let name = item.loaded.recipe.name
                Text(item.isOn ? name : String(localized: "\(name) (off)")).foregroundStyle(.secondary)
            }
        }
    }
}

/// "On Error / Failure": default, route to a step, forward to another recipe (upstream xaml:3090-3125).
private struct RecipeOnErrorSection: View {
    @ObservedObject var model: RecipeEditorModel
    let node: RecipeNode

    var body: some View {
        let mode = Binding<String>(get: {
            if node.onErrorRecipeId != nil { return "recipe" }
            return node.onErrorNodeId == nil ? "default" : "step"
        }, set: { choice in
            model.editNode(node.id) { edited in
                switch choice {
                case "step":
                    edited.onErrorRecipeId = nil
                    edited.onErrorNodeId = model.recipe?.nodes.first { $0.id != node.id }?.id ?? ""
                case "recipe":
                    edited.onErrorNodeId = nil
                    edited.onErrorRecipeId = model.library?.recipes.first { $0.recipe.id != model.recipe?.id }?.recipe.id ?? ""
                default:
                    edited.onErrorNodeId = nil
                    edited.onErrorRecipeId = nil
                }
            }
        })
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP ERROR HANDLING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            RecipeLabeled(String(localized: "On Error / Failure")) {
                Picker("", selection: mode) {
                    Text("Default (Use Recipe Fallback / Terminate)").tag("default")
                    Text("Route to Step in this Recipe…").tag("step")
                    Text("Forward to another Recipe…").tag("recipe")
                }
                .labelsHidden()
                .width(atLeast: 320)
            }
            if mode.wrappedValue == "step" {
                RecipeLabeled(String(localized: "Fallback Step")) {
                    RecipeNodePicker(model: model, selection: Binding(get: { node.onErrorNodeId ?? "" },
                                                                      set: { id in model.editNode(node.id) { $0.onErrorNodeId = id } }),
                                     excluding: node.id)
                }
            } else if mode.wrappedValue == "recipe" {
                RecipeLabeled(String(localized: "Fallback Recipe")) {
                    RecipeRecipePicker(model: model, selection: Binding(get: { node.onErrorRecipeId ?? "" },
                                                                        set: { id in model.editNode(node.id) { $0.onErrorRecipeId = id } }))
                }
            }
        }
    }
}

// MARK: Shared pieces

/// A label column and a control.
struct RecipeLabeled<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).frame(width: 168, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A step of the recipe (by id).
struct RecipeNodePicker: View {
    @ObservedObject var model: RecipeEditorModel
    @Binding var selection: String
    var excluding: String?
    var allowAny = false

    var body: some View {
        let nodes = (model.recipe?.nodes ?? []).filter { $0.id != excluding }
        Picker("", selection: $selection) {
            if allowAny { Text("* (any step)").tag("*") }
            ForEach(nodes, id: \.id) { node in Text("\(node.displayName) [\(node.id)]").tag(node.id) }
            if !selection.isEmpty, selection != "*", model.recipe?.node(selection) == nil {
                Text("\(selection) (missing)").tag(selection)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 320)
    }
}

/// Another recipe of the library (by id), or a typed id.
struct RecipeRecipePicker: View {
    @ObservedObject var model: RecipeEditorModel
    @Binding var selection: String

    var body: some View {
        let recipes = (model.library?.recipes ?? []).map(\.recipe).filter { $0.id != model.recipe?.id }
        HStack {
            if !recipes.isEmpty {
                Picker("", selection: $selection) {
                    ForEach(recipes, id: \.id) { recipe in Text("\(recipe.name) [\(recipe.id)]").tag(recipe.id) }
                    if !selection.isEmpty, !recipes.contains(where: { $0.id == selection }) { Text(selection).tag(selection) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            TextField("recipe id", text: $selection).textFieldStyle(.roundedBorder).frame(width: 160)
        }
    }
}

/// Errors and warnings of one place.
struct RecipeDiagnosticList: View {
    let diagnostics: [RecipeDiagnostic]

    var body: some View {
        if !diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(diagnostics) { diagnostic in
                    Label {
                        Text(diagnostic.message).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: diagnostic.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(diagnostic.isError ? Color.red : Color.orange)
                    }
                    .font(.callout)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
        }
    }
}

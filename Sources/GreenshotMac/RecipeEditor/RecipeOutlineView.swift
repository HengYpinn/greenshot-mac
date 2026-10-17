// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The steps as a list (`RecipeOutline`): what upstream's canvas shows with nodes and wires (RCP-280, RCP-284..286,
/// RCP-306). Context menus: start step, insert, parallel branch, continue at, move, delete.
struct RecipeOutlineView: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        List(selection: $model.selectedRow) {
            ForEach(model.outline.rows) { row in
                RecipeOutlineRowView(model: model, row: row)
                    .padding(.leading, CGFloat(row.depth) * 16)
                    .tag(row.id)
            }
            if model.outline.rows.isEmpty {
                RecipeAddStepMenu(model: model, title: "Add the first step") { model.addStep($0) }
                    .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct RecipeOutlineRowView: View {
    @ObservedObject var model: RecipeEditorModel
    let row: RecipeOutlineRow

    var body: some View {
        switch row.kind {
        case .step(let nodeId):
            RecipeStepRow(model: model, nodeId: nodeId)
        case .parallel(let from):
            RecipeGroupRow(symbol: "arrow.triangle.branch", title: from == nil ? "Parallel start" : "Parallel",
                           detail: "These lanes run at the same time") {
                RecipeAddStepMenu(model: model, title: "Add Lane") { model.insertStep($0, at: .parallel(from: from)) }
            }
        case .lane(let from, let index, let target):
            RecipeGroupRow(symbol: "arrow.down.right", title: "Lane \(index + 1)", detail: nil) {
                RecipeAddStepMenu(model: model, title: "Insert") { model.insertStep($0, at: .between(from: from, to: target, branch: nil)) }
            }
        case .branch(let from, let key, let expression, let label):
            RecipeGroupRow(symbol: "arrow.turn.down.right", title: branchTitle(key: key, expression: expression, label: label),
                           detail: nil) {
                RecipeAddStepMenu(model: model, title: "Insert") { model.insertStep($0, at: .branch(decision: from, key: key)) }
            }
        case .continues(let from, let branch, let to):
            RecipeContinuesRow(model: model, from: from, branch: branch, to: to)
        case .notReached:
            RecipeGroupRow(symbol: "exclamationmark.triangle", title: "Not reached",
                           detail: "No start step leads here: connect these steps with \"Continue At\"") { EmptyView() }
        case .extensionIn:
            RecipeGroupRow(symbol: "arrow.down.to.line", title: "In", detail: "Where the recipe's flow comes in") { EmptyView() }
        case .extensionOut:
            RecipeGroupRow(symbol: "arrow.down.forward", title: "Out", detail: "The recipe goes on") { EmptyView() }
        }
    }

    /// "If A: ${payload.width > 800}", "Otherwise (B)", "When the user picks 'Yes, Proceed'".
    private func branchTitle(key: String, expression: String?, label: String?) -> String {
        if let label { return "When the user picks '\(label)'" }
        guard let expression, !expression.isEmpty else { return "Branch \(key)" }
        let lower = expression.trimmingCharacters(in: .whitespaces).lowercased()
        if lower == "else" || lower == "default" { return "Otherwise (\(key))" }
        return "If \(key): \(expression)"
    }
}

/// A header row: a symbol, a title, a note and an action at the end.
private struct RecipeGroupRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 4)
            accessory()
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .controlSize(.small)
        }
        .padding(.vertical, 1)
    }
}

/// A step: icon, name, id, and its marks (start, off, problems, error route).
private struct RecipeStepRow: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String

    var body: some View {
        let node = model.recipe?.node(nodeId)
        let issues = model.diagnostics(for: .node(nodeId))
        let isStart = model.recipe.map { RecipeFlowEditor.isStart(nodeId, in: $0) } ?? false
        HStack(spacing: 6) {
            Image(systemName: RecipeEditorCatalog.symbol(for: node?.stepType ?? ""))
                .frame(width: 18)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(node?.displayName ?? nodeId)
                    .lineLimit(1)
                    .strikethrough(node?.enabled == .value(false))
                Text(subtitle(node))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isStart { Image(systemName: "star.fill").foregroundStyle(.green).help("Start step") }
            if node?.onErrorNodeId != nil || node?.onErrorRecipeId != nil {
                Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.secondary).help("Has its own error route")
            }
            if issues.contains(where: \.isError) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(issues.map(\.message).joined(separator: "\n"))
            } else if !issues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(issues.map(\.message).joined(separator: "\n"))
            }
        }
        .padding(.vertical, 2)
        .contextMenu { RecipeStepMenu(model: model, nodeId: nodeId) }
    }

    private func subtitle(_ node: RecipeNode?) -> String {
        guard let node else { return nodeId }
        var text = "\(node.stepType) · \(node.id)"
        if case .expression(let expression) = node.enabled { text += " · when \(expression)" }
        if node.enabled == .value(false) { text += " · off" }
        return text
    }
}

/// The context menu of a step (upstream xaml:370-372: Toggle Start Step, Delete Step; plus the list's own commands).
private struct RecipeStepMenu: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String

    var body: some View {
        let isStart = model.recipe.map { RecipeFlowEditor.isStart(nodeId, in: $0) } ?? false
        let targets = model.recipe.map { RecipeFlowEditor.connectableTargets(from: nodeId, in: $0) } ?? []
        Button(isStart ? "Remove Start Step" : "Mark as Start Step") { model.toggleStart(nodeId) }
        Divider()
        RecipeAddStepMenu(model: model, title: "Insert Step After") { model.insertStep($0, at: .after(nodeId)) }
        RecipeAddStepMenu(model: model, title: "Add Parallel Branch") { model.insertStep($0, at: .parallel(from: nodeId)) }
        Menu("Continue At") {
            ForEach(targets, id: \.self) { target in
                Button(target) { model.connect(from: nodeId, to: target, branch: nil) }
            }
        }
        .disabled(targets.isEmpty)
        Divider()
        Button("Move Up") { model.move(nodeId, up: true) }
        Button("Move Down") { model.move(nodeId, up: false) }
        Divider()
        Button("Delete Step") { model.deleteStep(nodeId) }
    }
}

/// "continues at: <step>" with a picker of the steps it may lead to, and Delete Connection.
private struct RecipeContinuesRow: View {
    @ObservedObject var model: RecipeEditorModel
    let from: String?
    let branch: String?
    let to: String

    var body: some View {
        let exists = model.recipe?.node(to) != nil
        let targets = from.flatMap { source in model.recipe.map { RecipeFlowEditor.connectableTargets(from: source, in: $0) } }
            ?? model.recipe?.nodes.map(\.id) ?? []
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).frame(width: 16)
            Text("continues at:").foregroundStyle(.secondary)
            Menu {
                ForEach(targets, id: \.self) { target in
                    Button(target) { model.retarget(from: from, branch: branch, old: to, new: target) }
                }
                Divider()
                Button("Delete Connection") { model.disconnect(from: from, to: to, branch: branch) }
            } label: {
                Text(exists ? (model.recipe?.node(to)?.displayName ?? to) : "\(to) (missing)")
                    .foregroundStyle(exists ? Color.primary : Color.red)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .font(.callout)
        .contextMenu {
            Button("Delete Connection") { model.disconnect(from: from, to: to, branch: branch) }
            RecipeAddStepMenu(model: model, title: "Insert Step Here") { model.insertStep($0, at: .between(from: from, to: to, branch: branch)) }
        }
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

/// The choices of the scope dialog while it is open: a copy, written back on OK.
@MainActor
final class RecipeScopeModel: ObservableObject {
    @Published var scope: RecipeExtensionScope

    init(scope: RecipeExtensionScope) {
        self.scope = scope
    }

    func setAll(captures: Bool, _ checked: Bool) {
        if captures {
            scope.captures = scope.captures.map { RecipeScopeItem(id: $0.id, name: $0.name, isChecked: checked) }
        } else {
            scope.destinations = scope.destinations.map { RecipeScopeItem(id: $0.id, name: $0.name, isChecked: checked) }
        }
    }

    func binding(captures: Bool, index: Int) -> Binding<Bool> {
        Binding(get: { [weak self] in
            guard let self else { return false }
            let items = captures ? self.scope.captures : self.scope.destinations
            return items.indices.contains(index) ? items[index].isChecked : false
        }, set: { [weak self] value in
            guard let self else { return }
            if captures {
                if self.scope.captures.indices.contains(index) { self.scope.captures[index].isChecked = value }
            } else if self.scope.destinations.indices.contains(index) {
                self.scope.destinations[index].isChecked = value
            }
        })
    }
}

/// "Where <automatic step> is used": the captures (recipes) and the destinations side by side, each with All and None
/// (RCP-230; upstream `Recipes/Views/RecipeExtensionScopeWindow.xaml`). OK needs at least one destination.
struct RecipeExtensionScopeSheet: View {
    let name: String
    @ObservedObject var model: RecipeScopeModel
    let done: (RecipeExtensionScope) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where \(name) is used").font(.headline)
            Text("This automatic step changes the captures of the checked recipes, for the checked destinations. New recipes get it too.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 20) {
                column("Captures", captures: true, items: model.scope.captures)
                if !model.scope.destinations.isEmpty {
                    column("Destinations", captures: false, items: model.scope.destinations)
                }
            }
            HStack {
                if !model.scope.isValid {
                    Text("Check at least one destination.").foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("OK") { done(model.scope) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.scope.isValid)
            }
        }
        .padding(20)
        .frame(width: model.scope.destinations.isEmpty ? 380 : 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func column(_ title: String, captures: Bool, items: [RecipeScopeItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Button("All") { model.setAll(captures: captures, true) }.buttonStyle(.link)
                Button("None") { model.setAll(captures: captures, false) }.buttonStyle(.link)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Toggle(item.name, isOn: model.binding(captures: captures, index: index))
                            .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 120, maxHeight: 360)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
        .frame(maxWidth: .infinity)
    }
}

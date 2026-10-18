// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

private let log = Log("RecipeEditor")

/// Where imported annotations come from: the open image editors or a .greenshot file (upstream
/// Helpers/EditorAnnotationImporter.cs, Views/SelectEditorWindow.xaml, Views/ImportAnnotationsWindow.xaml).
enum RecipeAnnotationImportSource: Identifiable {
    struct Editor: Identifiable {
        let id: UUID
        let title: String
        let image: CGImage
        let scale: CGFloat
        let elements: [Annotation]

        /// The picture with its elements, for the preview.
        var preview: CGImage {
            let document = EditorDocument(image: image, scale: scale, title: title, isModified: false)
            document.addOpened(elements)
            return document.flattened()
        }
    }

    case editors([Editor])
    case file(Editor)

    var id: String {
        switch self {
        case .editors(let list): return "editors:" + list.map(\.id.uuidString).joined()
        case .file(let editor): return "file:" + editor.id.uuidString
        }
    }

    /// The open image editors, sorted by title (upstream `ImageEditorForm.Editors`).
    @MainActor
    static func openEditors() -> [Editor] {
        guard let manager = (NSApp.delegate as? AppDelegate)?.editors else { return [] }
        return manager.openEditors.compactMap { open in
            guard let document = manager.document(for: open.id) else { return nil }
            return Editor(id: open.id, title: open.title, image: document.baseImage, scale: document.scale, elements: document.annotations)
        }
    }
}

/// Pick an editor (when several are open), then choose the elements: Append/Replace, per-element switches, A–Z,
/// pictures embedded (Base64) or saved to files `{prefix}_{type}_{n}.png`.
struct RecipeAnnotationImportView: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String
    let source: RecipeAnnotationImportSource
    let done: () -> Void
    @State private var chosen: RecipeAnnotationImportSource.Editor?

    var body: some View {
        Group {
            if let chosen {
                RecipeAnnotationImportForm(model: model, nodeId: nodeId, editor: chosen, done: done)
            } else {
                switch source {
                case .file(let editor):
                    RecipeAnnotationImportForm(model: model, nodeId: nodeId, editor: editor, done: done)
                case .editors(let editors):
                    RecipeSelectEditorView(editors: editors, choose: { chosen = $0 }, cancel: done)
                }
            }
        }
        .frame(width: 760, height: 520)
    }
}

/// Upstream "Select Image Editor": open editors on the left (title, canvas size, annotation count), the selected one's
/// picture on the right.
struct RecipeSelectEditorView: View {
    let editors: [RecipeAnnotationImportSource.Editor]
    let choose: (RecipeAnnotationImportSource.Editor) -> Void
    let cancel: () -> Void
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Image Editor").font(.headline).padding(10)
            Divider()
            if editors.isEmpty {
                Text("No image editor is open. Open a capture in the editor first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(editors, selection: $selection) { editor in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.title).lineLimit(1)
                            Text("\(editor.image.width) × \(editor.image.height) px · \(editor.elements.count == 1 ? String(localized: "1 annotation") : String(localized: "\(editor.elements.count) annotations"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(editor.id)
                    }
                    .frame(width: 260)
                    Divider()
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Import From This Editor") {
                    if let editor = editors.first(where: { $0.id == selection }) { choose(editor) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding(12)
        }
        .onAppear { selection = selection ?? editors.first?.id }
    }

    @ViewBuilder private var preview: some View {
        if let editor = editors.first(where: { $0.id == selection }) {
            Image(nsImage: NSImage(cgImage: editor.preview, size: NSSize(width: CGFloat(editor.image.width) / max(editor.scale, 1),
                                                                         height: CGFloat(editor.image.height) / max(editor.scale, 1))))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(radius: 2)
        } else {
            Text("Select an editor").foregroundStyle(.secondary)
        }
    }
}

/// Upstream "Import Annotations": the elements of an editor or file to put into the Annotation step.
struct RecipeAnnotationImportForm: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String
    let editor: RecipeAnnotationImportSource.Editor
    let done: () -> Void
    @State private var items: [RecipeAnnotationImportItem] = []
    @State private var included = Set<UUID>()
    @State private var sorted = false
    @State private var replace = false
    @State private var saveToFile = false
    @State private var folder: URL?
    @State private var prefix = ""

    var body: some View {
        let shown = sorted ? RecipeAnnotationExport.sortedAlphabetically(items) : items
        let hasPictures = items.contains(where: \.canSaveAsFile)
        VStack(alignment: .leading, spacing: 0) {
            Text("Import Annotations from \(editor.title)").font(.headline).padding(10)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(included.count) of \(items.count) elements").foregroundStyle(.secondary)
                        Spacer()
                        Toggle("A–Z", isOn: $sorted).toggleStyle(.button).controlSize(.small)
                        Button("All") { included = Set(items.map(\.id)) }.controlSize(.small)
                        Button("None") { included = [] }.controlSize(.small)
                    }
                    List(shown) { item in
                        Toggle(isOn: Binding(get: { included.contains(item.id) },
                                             set: { on in if on { included.insert(item.id) } else { included.remove(item.id) } })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.description).lineLimit(1)
                                Text(details(of: item)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: 380)
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Target step", selection: $replace) {
                        Text("Append to the annotations").tag(false)
                        Text("Replace the annotations").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    if hasPictures {
                        Picker("Pictures", selection: $saveToFile) {
                            Text("Embed (Base64)").tag(false)
                            Text("Save to File").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        if saveToFile {
                            HStack {
                                Text(folder?.path ?? String(localized: "No folder")).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                Button("Choose…") { chooseFolder() }
                            }
                            TextField("file name prefix", text: $prefix).textFieldStyle(.roundedBorder)
                            Text("Files: \(RecipeAnnotationExport.assetFileName(prefix: prefix, type: "image", index: 1, fileExtension: ".png")), …")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(12)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Import") { importSelected(shown) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(included.isEmpty || (saveToFile && folder == nil))
            }
            .padding(12)
        }
        .onAppear(perform: load)
    }

    /// "120 × 60" or "120 × 60 · picture".
    private func details(of item: RecipeAnnotationImportItem) -> String {
        guard item.canSaveAsFile else { return item.dimensions }
        return [item.dimensions, String(localized: "picture", comment: "An imported element is a picture")].joined(separator: " · ")
    }

    private func load() {
        items = RecipeAnnotationExport.items(of: editor.elements, scale: editor.scale)
        included = Set(items.map(\.id))
        prefix = model.recipe?.id ?? "asset"
        folder = model.fileURL?.deletingLastPathComponent() ?? model.environment.runtime()?.recipesFolder
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { folder = panel.url }
    }

    private func importSelected(_ shown: [RecipeAnnotationImportItem]) {
        let chosen = shown.filter { included.contains($0.id) }
        let storage: RecipeAssetStorage = saveToFile && folder != nil ? .saveToFile(folder: folder!, prefix: prefix) : .embed
        let imported = RecipeAnnotationExport.annotations(of: chosen, storage: storage) { data, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }.compactMap(\.objectValue)
        let count = imported.count
        let title = editor.title
        model.editNode(nodeId, String(localized: "Imported \(count) annotations from \(title)")) { node in
            let existing = replace ? [] : RecipeAnnotationSchema.annotations(of: node)
            node = RecipeAnnotationSchema.setting(existing + imported, in: node)
        }
        log.info("Imported \(imported.count) annotations into recipe step '\(nodeId)'.")
        done()
    }
}

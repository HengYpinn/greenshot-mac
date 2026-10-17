// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI
import UniformTypeIdentifiers

/// The Annotation step's list (upstream RecipeEditorWindow.xaml:1851-2540): add by type, reorder, A–Z, import from an open
/// editor or a .greenshot file, and the fields of the selected annotation by its type; QR codes reveal the fields of
/// their QR type and "Configure QR…" opens the QR dialog (RCP-301, RCP-302).
struct RecipeAnnotationsEditor: View {
    @ObservedObject var model: RecipeEditorModel
    let nodeId: String
    @State private var selected = 0
    @State private var importing: RecipeAnnotationImportSource?

    private var annotations: [JSONObject] {
        model.recipe?.node(nodeId).map(RecipeAnnotationSchema.annotations(of:)) ?? []
    }

    var body: some View {
        let list = annotations
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Annotations").font(.headline)
                Spacer()
                Menu("Add") {
                    ForEach(RecipeAnnotationSchema.types, id: \.self) { type in Button(type) { add(type) } }
                }
                .fixedSize()
                Menu("Import") {
                    Button("From Editor…") { importing = .editors(RecipeAnnotationImportSource.openEditors()) }
                    Button("From .greenshot File…") { importFromFile() }
                }
                .fixedSize()
                Button("A–Z") { sortByType() }.help("Sort the annotations by type")
            }
            if list.isEmpty {
                Text("No annotations yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { index, annotation in
                RecipeAnnotationListRow(summary: RecipeAnnotationSchema.summary(annotation), isSelected: index == selected,
                                        select: { selected = index }, moveUp: { move(index, by: -1) }, remove: { remove(index) },
                                        canMoveUp: index > 0)
            }
            if list.indices.contains(selected) {
                Divider()
                RecipeAnnotationForm(model: model, annotation: binding(selected))
            }
        }
        .sheet(item: $importing) { source in
            RecipeAnnotationImportView(model: model, nodeId: nodeId, source: source) { importing = nil }
        }
    }

    private func store(_ list: [JSONObject]) {
        model.editNode(nodeId) { node in node = RecipeAnnotationSchema.setting(list, in: node) }
    }

    private func binding(_ index: Int) -> Binding<JSONObject> {
        Binding(get: { annotations.indices.contains(index) ? annotations[index] : [:] },
                set: { object in
                    var list = annotations
                    guard list.indices.contains(index) else { return }
                    list[index] = object
                    store(list)
                })
    }

    private func add(_ type: String) {
        var annotation: JSONObject = ["Type": .string(type), "HorizontalAnchor": .string("Center"), "VerticalAnchor": .string("Center")]
        switch type.lowercased() {
        case "text", "speechbubble": annotation["Text"] = .string("Text")
        case "emoji": annotation["Emoji"] = .string("👍")
        case "qrcode": annotation["QrType"] = .string("Text"); annotation["Text"] = .string("https://getgreenshot.org")
        case "barcode": annotation["Format"] = .string("CODE_128"); annotation["Text"] = .string("GREENSHOT")
        case "freehand": annotation = ["Type": .string(type), "Points": .string("10,10;60,40;110,10")]
        default: annotation["Width"] = .number(120); annotation["Height"] = .number(60)
        }
        var list = annotations
        list.append(annotation)
        store(list)
        selected = list.count - 1
    }

    private func remove(_ index: Int) {
        var list = annotations
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        store(list)
        selected = min(selected, max(list.count - 1, 0))
    }

    private func move(_ index: Int, by offset: Int) {
        var list = annotations
        let target = index + offset
        guard list.indices.contains(index), list.indices.contains(target) else { return }
        list.swapAt(index, target)
        store(list)
        selected = target
    }

    private func sortByType() {
        let sorted = annotations.sorted {
            ($0.string("Type") ?? "").localizedStandardCompare($1.string("Type") ?? "") == .orderedAscending
        }
        store(sorted)
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Annotations from a Greenshot File")
        panel.allowedContentTypes = [UTType(filenameExtension: GreenshotFile.fileExtension) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let contents = GreenshotFile.read(contentsOf: url) else {
            let name = url.lastPathComponent
            model.status = String(localized: "\(name) could not be read as a Greenshot file.")
            return
        }
        importing = .file(RecipeAnnotationImportSource.Editor(id: UUID(), title: url.lastPathComponent, image: contents.image,
                                                              scale: contents.scale, elements: contents.elements))
    }
}

private struct RecipeAnnotationListRow: View {
    let summary: String
    let isSelected: Bool
    let select: () -> Void
    let moveUp: () -> Void
    let remove: () -> Void
    let canMoveUp: Bool

    var body: some View {
        HStack {
            Button(action: select) {
                Text(summary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: moveUp) { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(!canMoveUp)
            Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
    }
}

/// The fields of one annotation by its type.
private struct RecipeAnnotationForm: View {
    @ObservedObject var model: RecipeEditorModel
    @Binding var annotation: JSONObject

    var body: some View {
        let type = annotation.string("Type") ?? "Rectangle"
        let isCode = type.caseInsensitiveCompare("QRCode") == .orderedSame || type.caseInsensitiveCompare("Barcode") == .orderedSame
        VStack(alignment: .leading, spacing: 8) {
            RecipeLabeled("Type") {
                Picker("", selection: Binding(get: { RecipeAnnotationSchema.types.first { $0.caseInsensitiveCompare(type) == .orderedSame } ?? type },
                                              set: { annotation["Type"] = .string($0) })) {
                    ForEach(RecipeAnnotationSchema.types, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            ForEach(RecipeAnnotationSchema.fields(forType: type)) { field in
                switch field.name {
                case "FontFamily":
                    RecipeLabeled(field.label) { RecipeFontFamilyPicker(value: value(field.name)) }
                case "ImageData":
                    RecipeLabeled(field.label) { RecipeEmbedControl(value: value(field.name), svg: type.caseInsensitiveCompare("Svg") == .orderedSame) }
                default:
                    RecipeFieldRow(field: field, value: value(field.name))
                }
            }
            if isCode {
                Divider()
                ForEach(RecipeAnnotationSchema.qrFields(forType: annotation.string("QrType") ?? "Text")) { field in
                    RecipeFieldRow(field: field, value: value(field.name))
                }
                HStack {
                    Spacer()
                    Button("Configure QR…") { configure() }
                        .help("Edit the code with live preview")
                }
            }
        }
    }

    private func value(_ key: String) -> Binding<JSONValue?> {
        Binding(get: { annotation[key] }, set: { annotation[key] = $0 })
    }

    /// Upstream "⚙ Configure QR…" opens the Zxing editor: the Mac's QR dialog as a sheet.
    private func configure() {
        guard let window = model.window else { return }
        let sheet = BarcodeSheet(spec: RecipeAnnotationExport.spec(of: annotation), editing: true)
        sheet.onApply = { spec in annotation = RecipeAnnotationExport.applying(spec, to: annotation) }
        sheet.begin(for: window)
    }
}

/// The font families of the Mac (upstream's font controls).
private struct RecipeFontFamilyPicker: View {
    @Binding var value: JSONValue?

    var body: some View {
        let families = NSFontManager.shared.availableFontFamilies
        let current = value?.asString ?? ""
        Picker("", selection: Binding(get: { current }, set: { value = $0.isEmpty ? nil : .string($0) })) {
            Text("Default (system font)").tag("")
            if !current.isEmpty, !families.contains(current) { Text("\(current) (not installed)").tag(current) }
            ForEach(families, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(maxWidth: 260)
    }
}

/// An embedded picture (Base64): its size, "Embed File…" and "Remove" (upstream "Image Source": embed or link).
private struct RecipeEmbedControl: View {
    @Binding var value: JSONValue?
    var svg: Bool

    var body: some View {
        let bytes = value?.asString.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }?.count ?? 0
        HStack {
            Text(embedded(bytes))
                .foregroundStyle(.secondary)
            Button("Embed File…") { embed() }
            if bytes > 0 { Button("Remove") { value = nil } }
        }
    }

    private func embedded(_ bytes: Int) -> String {
        guard bytes > 0 else { return String(localized: "Nothing embedded") }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return String(localized: "\(size) embedded", comment: "The size of a picture embedded in a recipe")
    }

    private func embed() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = svg ? [.svg] : [.image]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        value = .string(data.base64EncodedString())
    }
}

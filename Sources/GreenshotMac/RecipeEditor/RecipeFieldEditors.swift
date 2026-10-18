// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI
import UniformTypeIdentifiers

/// One parameter of a generated form (upstream's specialised editors, RecipeEditorWindow.xaml:1086-3090): the label, the
/// control of its kind, and a menu to go back to the default or to a `${…}` expression.
struct RecipeFieldRow: View {
    let field: RecipeEditorField
    @Binding var value: JSONValue?
    var externalCommands: [String] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(field.label + (field.required ? " *" : ""))
                .frame(width: 168, alignment: .trailing)
                .help(field.help)
            VStack(alignment: .leading, spacing: 3) {
                control
                if !field.help.isEmpty {
                    Text(field.help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RecipeFieldMenu(field: field, value: $value)
        }
    }

    private var isExpression: Bool { RecipeParameterForm.isExpression(value) }

    @ViewBuilder private var control: some View {
        if isExpression, field.kind != .text, field.kind != .multilineText {
            RecipeTextControl(value: $value, placeholder: "${…}", multiline: false)
        } else {
            switch field.kind {
            case .text: RecipeTextControl(value: $value, placeholder: placeholder, multiline: false)
            case .multilineText: RecipeTextControl(value: $value, placeholder: placeholder, multiline: true)
            case .integer: RecipeNumberControl(value: $value, placeholder: placeholder, decimal: false)
            case .decimal: RecipeNumberControl(value: $value, placeholder: placeholder, decimal: true)
            case .boolean: RecipeBoolControl(value: $value, defaultValue: field.defaultValue?.asBool)
            case .choice(let values): RecipeChoiceControl(value: $value, values: values, defaultValue: field.defaultValue?.asString)
            case .color: RecipeColorControl(value: $value, placeholder: placeholder)
            case .filePath: RecipePathControl(value: $value, placeholder: placeholder, directory: false, sound: false)
            case .directoryPath: RecipePathControl(value: $value, placeholder: placeholder, directory: true, sound: false)
            case .soundFile: RecipePathControl(value: $value, placeholder: placeholder, directory: false, sound: true)
            case .stringList: RecipeStringListControl(value: $value, regex: field.name.caseInsensitiveCompare("Patterns") == .orderedSame)
            case .keyValueTable: RecipeKeyValueControl(value: $value)
            case .branchTable: RecipeBranchTableControl(value: $value)
            case .choiceTable: RecipeChoiceTableControl(value: $value)
            case .destinationList: RecipeDestinationListControl(value: $value, externalCommands: externalCommands)
            case .edges: RecipeEdgesControl(value: $value)
            case .accept: RecipeAcceptControl(value: $value)
            case .arguments: RecipeArgumentsControl(value: $value)
            case .hotkey: RecipeHotkeyControl(value: $value)
            case .annotations, .json: RecipeJSONValueControl(value: $value)
            }
        }
    }

    private var placeholder: String {
        guard let defaultValue = field.defaultValue else {
            return field.required ? String(localized: "required", comment: "Placeholder of a parameter that must be set")
                : String(localized: "default", comment: "Placeholder of a parameter that uses its default value")
        }
        let text = defaultValue.interpolationText
        return String(localized: "default: \(text)", comment: "Placeholder of a parameter: its default value")
    }
}

/// Default / expression / value.
private struct RecipeFieldMenu: View {
    let field: RecipeEditorField
    @Binding var value: JSONValue?

    var body: some View {
        Menu {
            Button("Use Default") { value = nil }
                .disabled(value == nil)
            if field.supportsExpressions {
                Button("Use Expression") { value = .string(value?.asString.map { $0.contains("${") ? $0 : "${\($0)}" } ?? "${}") }
                    .disabled(RecipeParameterForm.isExpression(value))
            }
        } label: {
            Image(systemName: value == nil ? "circle.dashed" : RecipeParameterForm.isExpression(value) ? "function" : "smallcircle.filled.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(value == nil ? "Default" : RecipeParameterForm.isExpression(value) ? "Expression" : "Set in the recipe")
    }
}

// MARK: Simple controls

struct RecipeTextControl: View {
    @Binding var value: JSONValue?
    var placeholder: String
    var multiline: Bool

    var body: some View {
        let text = Binding<String>(get: { value?.asString ?? "" }, set: { value = $0.isEmpty ? nil : .string($0) })
        if multiline {
            TextField(placeholder, text: text, axis: .vertical).lineLimit(2...8).textFieldStyle(.roundedBorder)
        } else {
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct RecipeNumberControl: View {
    @Binding var value: JSONValue?
    var placeholder: String
    var decimal: Bool

    var body: some View {
        let text = Binding<String>(get: { value?.asString ?? "" },
                                   set: { value = RecipeParameterForm.numberValue($0, decimal: decimal) })
        TextField(placeholder, text: text).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
    }
}

private struct RecipeBoolControl: View {
    @Binding var value: JSONValue?
    var defaultValue: Bool?

    var body: some View {
        let on = Binding<Bool>(get: { value?.asBool ?? defaultValue ?? false }, set: { value = .bool($0) })
        HStack {
            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
            if value == nil { Text("default").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct RecipeChoiceControl: View {
    @Binding var value: JSONValue?
    var values: [String]
    var defaultValue: String?

    var body: some View {
        let current = value?.asString
        let selection = Binding<String>(get: { current.map { text in values.first { $0.caseInsensitiveCompare(text) == .orderedSame } ?? text } ?? "" },
                                        set: { value = $0.isEmpty ? nil : .string($0) })
        Picker("", selection: selection) {
            Text(defaultValue.map { String(localized: "Default (\($0))") } ?? String(localized: "Default")).tag("")
            ForEach(values, id: \.self) { Text($0).tag($0) }
            if let current, !current.isEmpty, !values.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
                Text("\(current) (unknown)").tag(current)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 260)
    }
}

private struct RecipeColorControl: View {
    @Binding var value: JSONValue?
    var placeholder: String

    var body: some View {
        let text = value?.asString ?? ""
        let color = Binding<Color>(
            get: { RecipeEditorColors.parse(text).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? .clear },
            set: { newColor in
                let resolved = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                let rgba = RGBAColor(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent,
                                     alpha: resolved.alphaComponent)
                value = .string(RecipeEditorColors.format(rgba))
            })
        HStack {
            ColorPicker("", selection: color, supportsOpacity: true).labelsHidden()
            RecipeTextControl(value: $value, placeholder: placeholder, multiline: false).frame(maxWidth: 200)
            if !text.isEmpty, RecipeEditorColors.parse(text) == nil, !text.contains("${") {
                Text("not a colour").font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct RecipePathControl: View {
    @Binding var value: JSONValue?
    var placeholder: String
    var directory: Bool
    var sound: Bool

    var body: some View {
        HStack {
            RecipeTextControl(value: $value, placeholder: placeholder, multiline: false)
            Button("Choose…") { choose() }
            if sound {
                Button {
                    play()
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Play the sound")
                .disabled(value?.asString?.isEmpty ?? true)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        if sound { panel.allowedContentTypes = [.audio] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        value = .string(url.path)
    }

    private func play() {
        guard let path = value?.asString else { return }
        NSSound(contentsOfFile: (path as NSString).expandingTildeInPath, byReference: true)?.play()
    }
}

/// Any JSON value as text, applied when it parses.
private struct RecipeJSONValueControl: View {
    @Binding var value: JSONValue?
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("JSON", text: $text, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...10)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            HStack {
                Button("Apply", action: apply).controlSize(.small)
                if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            }
        }
        .onAppear { text = value?.serialized(indented: false) ?? "" }
        .onChange(of: value) { _, newValue in text = newValue?.serialized(indented: false) ?? "" }
    }

    private func apply() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            value = nil
            problem = nil
            return
        }
        do {
            value = try JSONValue.parse(trimmed)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

// MARK: Lists and tables

/// One text per line (Patterns: each must be a regular expression).
private struct RecipeStringListControl: View {
    @Binding var value: JSONValue?
    var regex: Bool

    var body: some View {
        let lines = Binding<String>(get: { (value?.asStrings ?? []).joined(separator: "\n") },
                                    set: { text in
                                        let items = text.components(separatedBy: "\n")
                                        value = .array(items.map { .string($0) })
                                    })
        VStack(alignment: .leading, spacing: 2) {
            TextField("one per line", text: lines, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...10)
                .textFieldStyle(.roundedBorder)
            if regex, let problem = invalidPattern {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var invalidPattern: String? {
        for pattern in value?.asStrings ?? [] where !pattern.isEmpty && !pattern.contains("${") {
            if (try? NSRegularExpression(pattern: pattern)) == nil { return String(localized: "Not a regular expression: \(pattern)") }
        }
        return nil
    }
}

/// Name → value (SetVariable `Variables`).
private struct RecipeKeyValueControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        let object = value?.objectValue ?? [:]
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(object.members.enumerated()), id: \.offset) { index, member in
                HStack {
                    TextField("name", text: Binding(get: { member.key }, set: { rename(index, to: $0) }))
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                    TextField("value", text: Binding(get: { member.value.asString ?? member.value.serialized(indented: false) },
                                                     set: { set(index, $0) }))
                        .textFieldStyle(.roundedBorder)
                    Button { remove(index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Variable") { add() }.controlSize(.small)
        }
    }

    private func members() -> [JSONMember] { value?.objectValue?.members ?? [] }

    private func store(_ members: [JSONMember]) { value = .object(JSONObject(members)) }

    private func rename(_ index: Int, to key: String) {
        var list = members()
        guard list.indices.contains(index) else { return }
        list[index].key = key
        store(list)
    }

    private func set(_ index: Int, _ text: String) {
        var list = members()
        guard list.indices.contains(index) else { return }
        list[index].value = .string(text)
        store(list)
    }

    private func remove(_ index: Int) {
        var list = members()
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        store(list)
    }

    private func add() {
        var list = members()
        var name = "variable"
        var number = 2
        while list.contains(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "variable\(number)"
            number += 1
        }
        list.append(JSONMember(name, .string("")))
        store(list)
    }
}

/// A list of objects edited row by row.
private struct RecipeObjectList<Row: View>: View {
    @Binding var value: JSONValue?
    var addTitle: String
    var newItem: (Int) -> JSONObject
    @ViewBuilder var row: (Binding<JSONObject>) -> Row

    var body: some View {
        let items = value?.arrayValue ?? []
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                HStack(alignment: .firstTextBaseline) {
                    row(binding(index))
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0)
                    Button { remove(index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button(addTitle) { value = .array(items + [.object(newItem(items.count))]) }.controlSize(.small)
        }
    }

    private func binding(_ index: Int) -> Binding<JSONObject> {
        Binding(get: { value?.arrayValue.flatMap { $0.indices.contains(index) ? $0[index].objectValue : nil } ?? [:] },
                set: { object in
                    var items = value?.arrayValue ?? []
                    guard items.indices.contains(index) else { return }
                    items[index] = .object(object)
                    value = .array(items)
                })
    }

    private func remove(_ index: Int) {
        var items = value?.arrayValue ?? []
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        value = .array(items)
    }

    private func move(_ index: Int, by offset: Int) {
        var items = value?.arrayValue ?? []
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
        value = .array(items)
    }
}

/// A text member of an object.
private func member(_ object: Binding<JSONObject>, _ key: String) -> Binding<String> {
    Binding(get: { object.wrappedValue.string(key) ?? "" }, set: { object.wrappedValue[key] = .string($0) })
}

private func flag(_ object: Binding<JSONObject>, _ key: String) -> Binding<Bool> {
    Binding(get: { object.wrappedValue.bool(key) ?? false }, set: { object.wrappedValue[key] = .bool($0) })
}

/// Conditional `Branches`: key and expression; "else"/"default" always matches (upstream xaml "Condition Branches").
private struct RecipeBranchTableControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        RecipeObjectList(value: $value, addTitle: String(localized: "Add Branch"),
                         newItem: { ["key": .string(String(UnicodeScalar(UInt8(65 + min($0, 25))))), "expression": .string("else")] }) { object in
            TextField("key", text: member(object, "key")).textFieldStyle(.roundedBorder).frame(width: 70)
            TextField("expression, e.g. ${payload.width > 800} or else", text: member(object, "expression"))
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
        }
    }
}

/// UserPrompt `Choices`: key, label, style, default, cancel (upstream `PromptChoice`).
private struct RecipeChoiceTableControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        RecipeObjectList(value: $value, addTitle: String(localized: "Add Choice"),
                         newItem: { ["Key": .string("Choice\($0 + 1)"), "Label": .string("Choice \($0 + 1)"), "Style": .string("Secondary")] }) { object in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    TextField("key", text: member(object, "Key")).textFieldStyle(.roundedBorder).frame(width: 90)
                    TextField("button label", text: member(object, "Label")).textFieldStyle(.roundedBorder)
                }
                // The switches below the style when they don't fit beside it (longer languages).
                ViewThatFits(in: .horizontal) {
                    HStack {
                        stylePicker(object)
                        switches(object)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        stylePicker(object)
                        HStack { switches(object) }
                    }
                }
            }
        }
    }
}

private func stylePicker(_ object: Binding<JSONObject>) -> some View {
    Picker("", selection: member(object, "Style")) {
        ForEach(["Primary", "Secondary", "Danger"], id: \.self) { Text($0).tag($0) }
    }
    .labelsHidden().frame(width: 120)
}

@ViewBuilder private func switches(_ object: Binding<JSONObject>) -> some View {
    Toggle("Default (Return)", isOn: flag(object, "IsDefault")).controlSize(.small).fixedSize()
    Toggle("Cancel (Esc)", isOn: flag(object, "IsCancel")).controlSize(.small).fixedSize()
}

/// Commandline / AiTool `Arguments` (upstream `CommandlineArgument`).
private struct RecipeArgumentsControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        RecipeObjectList(value: $value, addTitle: String(localized: "Add Argument"),
                         newItem: { ["name": .string("arg\($0 + 1)"), "type": .string("String")] }) { object in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    TextField("name", text: member(object, "name")).textFieldStyle(.roundedBorder).frame(width: 120)
                    Picker("", selection: member(object, "type")) {
                        ForEach(ContractDataType.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                    Toggle("Required", isOn: flag(object, "required")).controlSize(.small).fixedSize()
                }
                HStack {
                    TextField("variable (default: the name)", text: member(object, "variable")).textFieldStyle(.roundedBorder)
                    TextField("default", text: member(object, "defaultValue")).textFieldStyle(.roundedBorder).frame(width: 110)
                }
                TextField("description", text: member(object, "description")).textFieldStyle(.roundedBorder)
            }
        }
    }
}

/// Destination designations (upstream "Export Destinations"): the Mac's destinations by upstream designation, the
/// external commands, and any other text.
private struct RecipeDestinationListControl: View {
    @Binding var value: JSONValue?
    var externalCommands: [String]
    @State private var custom = ""

    var body: some View {
        let listed = value?.asStrings ?? []
        VStack(alignment: .leading, spacing: 4) {
            if listed.isEmpty { Text("default: the destinations of the settings").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(listed.enumerated()), id: \.offset) { index, designation in
                HStack {
                    Text(RecipeDestinationDesignation(designation).displayName)
                    Spacer()
                    Button { remove(index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Menu("Add Destination") {
                    ForEach(CaptureDestination.allCases, id: \.self) { destination in
                        let designation = RecipeDestinationDesignation.designation(for: destination)
                        if destination != .externalCommand {
                            Button(RecipeDestinationDesignation(designation).displayName) { add(designation) }
                        }
                    }
                    if !externalCommands.isEmpty {
                        Divider()
                        ForEach(externalCommands, id: \.self) { name in
                            Button("External command \(name)") { add("External \(name)") }
                        }
                    }
                }
                .fixedSize()
                TextField("or a designation", text: $custom).textFieldStyle(.roundedBorder).frame(width: 160)
                    .onSubmit {
                        add(custom)
                        custom = ""
                    }
            }
        }
    }

    private func add(_ designation: String) {
        let trimmed = designation.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        value = .array((value?.asStrings ?? []).map { .string($0) } + [.string(trimmed)])
    }

    private func remove(_ index: Int) {
        var list = value?.asStrings ?? []
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        value = list.isEmpty ? nil : .array(list.map { .string($0) })
    }
}

/// Torn edges: top, right, bottom, left (four bools, as the Effect step reads them).
private struct RecipeEdgesControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        HStack {
            let sides = [String(localized: "Top"), String(localized: "Right", comment: "The right side of the capture"),
                         String(localized: "Bottom"), String(localized: "Left", comment: "The left side of the capture")]
            ForEach(Array(sides.enumerated()), id: \.offset) { index, name in
                Toggle(name, isOn: Binding(get: { flags()[index] }, set: { set(index, $0) })).controlSize(.small)
            }
        }
    }

    private func flags() -> [Bool] {
        if let items = value?.arrayValue?.compactMap(\.asBool), items.count == 4 { return items }
        if let text = value?.stringValue?.lowercased(), !text.isEmpty {
            return ["top", "right", "bottom", "left"].map { text.contains($0) }
        }
        return [true, true, true, true]
    }

    private func set(_ index: Int, _ on: Bool) {
        var list = flags()
        list[index] = on
        value = .array(list.map { .bool($0) })
    }
}

/// Slot `Accept`: all, none, or the ids of automatic steps.
private struct RecipeAcceptControl: View {
    @Binding var value: JSONValue?

    var body: some View {
        let mode = Binding<String>(get: {
            if let text = value?.stringValue?.lowercased(), text == "all" || text == "none" { return text }
            return value == nil ? "all" : "list"
        }, set: { choice in
            switch choice {
            case "all", "none": value = .string(choice)
            default: value = .array([])
            }
        })
        let ids = Binding<String>(get: { value?.arrayValue == nil ? "" : (value?.asStrings ?? []).joined(separator: ", ") },
                                  set: { text in
                                      let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                      value = .array(items.map { .string($0) })
                                  })
        HStack {
            Picker("", selection: mode) {
                Text("All").tag("all")
                Text("None").tag("none")
                Text("These:").tag("list")
            }
            .labelsHidden().frame(width: 100)
            if mode.wrappedValue == "list" {
                TextField("ext_border, ext_caption", text: ids).textFieldStyle(.roundedBorder)
            }
        }
    }
}

/// The Hotkey trigger's "Ctrl + Shift + B" with the recorder of Settings (Ctrl is ⌘ on the Mac).
private struct RecipeHotkeyControl: View {
    @Binding var value: JSONValue?
    @State private var problem: String?

    var body: some View {
        let combo = Binding<KeyCombo?>(get: { value?.asString.flatMap(RecipeHotkeyText.parse) },
                                       set: { value = $0.map { .string(RecipeHotkeyText.format($0)) } })
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                ShortcutRecorder(combo: combo, problem: $problem)
                Text(value?.asString ?? "").font(.caption).foregroundStyle(.secondary)
            }
            if let text = value?.asString, let issue = RecipeHotkeyText.problem(with: text) {
                Text(issue).font(.caption).foregroundStyle(.red)
            } else if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

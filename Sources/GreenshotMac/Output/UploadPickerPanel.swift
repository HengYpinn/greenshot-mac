// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The dialog before an upload to Jira or Confluence: port of upstream `JiraUploadWindow` and
/// `ConfluenceUploadWindow`. A key (Jira) or a search, a list of results (the recent ones first), the file name and
/// a comment, then Upload.
@MainActor
final class UploadPickerPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSComboBoxDelegate {
    struct Row: Equatable {
        var id: String
        var primary: String
        var secondary: String
    }

    struct Choice {
        /// The picked row, or nil when a key was typed.
        var row: Row?
        var typedKey: String
        var filename: String
        var comment: String
    }

    struct Configuration {
        var title: String
        /// The label of the key field (Jira: "Issue key"); nil when only a picked row counts (Confluence).
        var keyLabel: String?
        var searchPlaceholder: String
        var columns: (String, String)
        var recent: [Row]
        var filename: String
        var showsComment: Bool
        /// Whether a typed key is enough to upload.
        var acceptsKey: (String) -> Bool = { _ in false }
        var search: (String) async throws -> [Row]
    }

    private let configuration: Configuration
    private let window: NSWindow
    private let keyField = NSComboBox()
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let filenameField = NSTextField()
    private let commentField = NSTextField()
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)
    private var rows: [Row] = []
    private var searchTask: Task<Void, Never>?
    private var accepted = false

    init(_ configuration: Configuration) {
        self.configuration = configuration
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = configuration.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        rows = configuration.recent
        build()
    }

    /// Runs the dialog; nil when cancelled.
    func run() -> Choice? {
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.initialFirstResponder = configuration.keyLabel == nil ? searchField : keyField
        NSApp.runModal(for: window)
        searchTask?.cancel()
        window.orderOut(nil)
        guard accepted else { return nil }
        let selected = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil
        return Choice(row: selected, typedKey: keyField.stringValue, filename: filenameField.stringValue,
                      comment: commentField.stringValue)
    }

    private func build() {
        var gridRows: [[NSView]] = []
        if let keyLabel = configuration.keyLabel {
            keyField.addItems(withObjectValues: configuration.recent.map(\.id))
            keyField.placeholderString = "e.g. PROJ-123"
            keyField.completes = true
            keyField.delegate = self
            gridRows.append([label("\(keyLabel):"), keyField])
        }
        searchField.placeholderString = configuration.searchPlaceholder
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(search)
        gridRows.append([label("Search:"), searchField])

        for (index, title) in [configuration.columns.0, configuration.columns.1].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.title = title
            column.width = index == 0 ? 150 : 320
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.target = self
        table.doubleAction = #selector(accept)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        gridRows.append([label(""), scroll])
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.stringValue = configuration.recent.isEmpty ? "" : "Recent"
        gridRows.append([label(""), status])

        filenameField.stringValue = configuration.filename
        gridRows.append([label("File name:"), filenameField])
        if configuration.showsComment {
            commentField.placeholderString = "Optional"
            gridRows.append([label("Comment:"), commentField])
        }
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        uploadButton.target = self
        uploadButton.action = #selector(accept)
        uploadButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, uploadButton])
        buttons.orientation = .horizontal
        gridRows.append([label(""), buttons])

        let grid = NSGridView(views: gridRows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            buttons.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
        ])
        window.contentView = content
        updateUploadButton()
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    @objc private func search() {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard !text.isEmpty else {
            show(rows: configuration.recent, status: configuration.recent.isEmpty ? "" : "Recent")
            return
        }
        status.stringValue = "Searching…"
        let search = configuration.search
        searchTask = Task { @MainActor [weak self] in
            do {
                let found = try await search(text)
                guard !Task.isCancelled else { return }
                self?.show(rows: found, status: found.isEmpty ? "Nothing found" : "\(found.count) found")
            } catch {
                guard !Task.isCancelled else { return }
                self?.show(rows: [], status: error.localizedDescription)
            }
        }
    }

    private func show(rows: [Row], status text: String) {
        self.rows = rows
        table.reloadData()
        status.stringValue = text
        if rows.count == 1 { table.selectRowIndexes([0], byExtendingSelection: false) }
        updateUploadButton()
    }

    private func updateUploadButton() {
        let picked = table.selectedRow >= 0 && table.selectedRow < rows.count
        uploadButton.isEnabled = picked || (configuration.keyLabel != nil && configuration.acceptsKey(keyField.stringValue))
    }

    @objc private func accept() {
        guard uploadButton.isEnabled else { return }
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        NSApp.stopModal()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }

    // The key field: typing a key selects nothing in the list; picking a row fills the key.

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSComboBox) === keyField else { return }
        if table.selectedRow >= 0, table.selectedRow < rows.count, rows[table.selectedRow].id != JiraClient.normalizedKey(keyField.stringValue) {
            table.deselectAll(nil)
        }
        updateUploadButton()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateUploadButton() }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if configuration.keyLabel != nil, table.selectedRow >= 0, table.selectedRow < rows.count {
            keyField.stringValue = rows[table.selectedRow].id
        }
        updateUploadButton()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = tableColumn?.identifier.rawValue == "c0" ? rows[row].primary : rows[row].secondary
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = text
        return cell
    }
}

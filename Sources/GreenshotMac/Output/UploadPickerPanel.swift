// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The dialog before an upload to Jira or Confluence: port of upstream `JiraUploadWindow` and
/// `ConfluenceUploadWindow`. A key (Jira) or a search, a filter or a space to choose from, a list of results (the
/// recent ones first, sortable by every column), the file name and a comment, then Upload.
@MainActor
final class UploadPickerPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSComboBoxDelegate {
    struct Row: Equatable {
        var id: String
        /// One text per column.
        var values: [String]
        /// What a column sorts by when it isn't its text (e.g. a date); nil sorts by `values`.
        var sortKeys: [String]?
        /// The picture of the column that shows icons (upstream's issue type icons).
        var iconURL: URL?

        init(id: String, values: [String], sortKeys: [String]? = nil, iconURL: URL? = nil) {
            self.id = id
            self.values = values
            self.sortKeys = sortKeys
            self.iconURL = iconURL
        }
    }

    struct Column {
        var title: String
        var width: CGFloat
        /// The column shows the row's icon before its text.
        var showsIcon = false
    }

    /// A Jira filter or a Confluence space.
    struct Scope: Equatable {
        var id: String
        var title: String
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
        var columns: [Column]
        var recent: [Row]
        var filename: String
        var showsComment: Bool
        /// Whether a typed key is enough to upload.
        var acceptsKey: (String) -> Bool = { _ in false }
        /// The search with the scope chosen (nil: all).
        var search: (String, Scope?) async throws -> [Row]
        /// The scope popup ("Filter:", "Space:"); nil without one.
        var scopeLabel: String? = nil
        /// The popup's first entry, which means no scope ("All spaces").
        var noScopeTitle = ""
        var loadScopes: (() async throws -> [Scope])? = nil
        var initialScopeID: String? = nil
        /// Picking a scope lists its rows (a Jira filter); without it a scope only limits the search (a space).
        var listScope: ((Scope) async throws -> [Row])? = nil
        var scopeChanged: (Scope?) -> Void = { _ in }
        /// Loads a row icon.
        var loadIcon: ((URL) async -> NSImage?)? = nil
    }

    private let configuration: Configuration
    private let window: NSWindow
    private let keyField = NSComboBox()
    private let searchField = NSSearchField()
    private let scopePopup = NSPopUpButton()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let filenameField = NSTextField()
    private let commentField = NSTextField()
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)
    private var rows: [Row] = []
    private var scopes: [Scope] = []
    private var icons: [URL: NSImage] = [:]
    private var loadingIcons: Set<URL> = []
    private var searchTask: Task<Void, Never>?
    private var scopeTask: Task<Void, Never>?
    private var accepted = false

    init(_ configuration: Configuration) {
        self.configuration = configuration
        let width = max(540, configuration.columns.reduce(0) { $0 + $1.width } + 150)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 480), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = configuration.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        rows = configuration.recent
        build()
    }

    /// The window's content, for the snapshots.
    var contentView: NSView? { window.contentView }

    /// Runs the dialog; nil when cancelled.
    func run() -> Choice? {
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.initialFirstResponder = configuration.keyLabel == nil ? searchField : keyField
        loadScopes()
        NSApp.runModal(for: window)
        searchTask?.cancel()
        scopeTask?.cancel()
        window.orderOut(nil)
        guard accepted else { return nil }
        let selected = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil
        return Choice(row: selected, typedKey: keyField.stringValue, filename: filenameField.stringValue,
                      comment: commentField.stringValue)
    }

    /// Shows rows and scopes without a server, for the snapshots.
    func preview(rows: [Row], scopes: [Scope], selectedScope: String?, icons: [URL: NSImage] = [:]) {
        self.icons = icons
        fillScopes(scopes, select: selectedScope)
        show(rows: rows, status: "\(rows.count) found")
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
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
        if let scopeLabel = configuration.scopeLabel {
            scopePopup.addItem(withTitle: configuration.noScopeTitle)
            scopePopup.target = self
            scopePopup.action = #selector(scopeChosen)
            gridRows.append([label("\(scopeLabel):"), scopePopup])
        }
        searchField.placeholderString = configuration.searchPlaceholder
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(search)
        gridRows.append([label("Search:"), searchField])

        for (index, column) in configuration.columns.enumerated() {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "c\(index)", ascending: true)
            table.addTableColumn(tableColumn)
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
        scroll.hasHorizontalScroller = true
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

    // MARK: Scopes

    private func loadScopes() {
        guard let load = configuration.loadScopes else { return }
        scopePopup.isEnabled = false
        scopeTask = Task { @MainActor [weak self] in
            do {
                let found = try await load()
                guard !Task.isCancelled, let self else { return }
                self.fillScopes(found, select: self.configuration.initialScopeID)
            } catch {
                guard !Task.isCancelled else { return }
                self?.scopePopup.isEnabled = true
                self?.status.stringValue = error.localizedDescription
            }
        }
    }

    private func fillScopes(_ found: [Scope], select id: String?) {
        scopes = found
        scopePopup.removeAllItems()
        scopePopup.addItem(withTitle: configuration.noScopeTitle)
        for scope in found {
            scopePopup.addItem(withTitle: scope.title)
        }
        scopePopup.isEnabled = true
        if let id, let index = found.firstIndex(where: { $0.id == id }) {
            scopePopup.selectItem(at: index + 1)
        }
    }

    private var selectedScope: Scope? {
        let index = scopePopup.indexOfSelectedItem - 1
        return scopes.indices.contains(index) ? scopes[index] : nil
    }

    @objc private func scopeChosen() {
        let scope = selectedScope
        configuration.scopeChanged(scope)
        if let scope, let list = configuration.listScope {
            run(status: "Loading \(scope.title)…") { try await list(scope) }
        } else if !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            search()
        } else if scope == nil {
            show(rows: configuration.recent, status: configuration.recent.isEmpty ? "" : "Recent")
        }
    }

    // MARK: Search

    @objc private func search() {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            searchTask?.cancel()
            show(rows: configuration.recent, status: configuration.recent.isEmpty ? "" : "Recent")
            return
        }
        let search = configuration.search
        let scope = configuration.listScope == nil ? selectedScope : nil
        run(status: "Searching…") { try await search(text, scope) }
    }

    private func run(status text: String, _ load: @escaping @MainActor () async throws -> [Row]) {
        searchTask?.cancel()
        status.stringValue = text
        searchTask = Task { @MainActor [weak self] in
            do {
                let found = try await load()
                guard !Task.isCancelled else { return }
                self?.show(rows: found, status: found.isEmpty ? "Nothing found" : "\(found.count) found")
            } catch {
                guard !Task.isCancelled else { return }
                self?.show(rows: [], status: error.localizedDescription)
            }
        }
    }

    private func show(rows: [Row], status text: String) {
        self.rows = sorted(rows)
        table.reloadData()
        status.stringValue = text
        if self.rows.count == 1 { table.selectRowIndexes([0], byExtendingSelection: false) }
        updateUploadButton()
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        guard let descriptor = table.sortDescriptors.first, let key = descriptor.key,
              let column = Int(key.dropFirst()) else { return rows }
        func value(_ row: Row) -> String {
            let keys = row.sortKeys ?? row.values
            return column < keys.count ? keys[column] : ""
        }
        return rows.sorted { a, b in
            let order = value(a).localizedStandardCompare(value(b))
            return descriptor.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let selectedID = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow].id : nil
        rows = sorted(rows)
        table.reloadData()
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes([index], byExtendingSelection: false)
        }
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
        guard let tableColumn, let index = Int(tableColumn.identifier.rawValue.dropFirst()), row < rows.count else { return nil }
        let entry = rows[row]
        let showsIcon = index < configuration.columns.count && configuration.columns[index].showsIcon
        let identifier = NSUserInterfaceItemIdentifier(showsIcon ? "iconCell" : "cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier, icon: showsIcon)
        cell.textField?.stringValue = index < entry.values.count ? entry.values[index] : ""
        if showsIcon {
            cell.imageView?.image = entry.iconURL.flatMap { icon(for: $0) }
        }
        return cell
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier, icon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        var leading = cell.leadingAnchor
        if icon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
            ])
            leading = image.trailingAnchor
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leading, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// The icon from the cache; a missing one is loaded and its rows redrawn when it arrives.
    private func icon(for url: URL) -> NSImage? {
        if let cached = icons[url] { return cached }
        guard let load = configuration.loadIcon, !loadingIcons.contains(url) else { return nil }
        loadingIcons.insert(url)
        Task { @MainActor [weak self] in
            guard let image = await load(url), let self else { return }
            self.icons[url] = image
            let changed = IndexSet(self.rows.indices.filter { self.rows[$0].iconURL == url })
            let iconColumns = IndexSet(self.configuration.columns.indices.filter { self.configuration.columns[$0].showsIcon })
            self.table.reloadData(forRowIndexes: changed, columnIndexes: iconColumns)
        }
        return nil
    }
}

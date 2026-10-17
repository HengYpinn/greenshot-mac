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
final class UploadPickerPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSComboBoxDelegate,
    NSTabViewDelegate {
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
        /// The row was picked in the "Open pages" tab (upstream `IsOpenPageSelected`: the page is open already).
        var fromOpenRows = false
    }

    /// The "Open pages" tab: rows found elsewhere (the browser's tabs), possibly only after the user asks.
    struct OpenRows {
        var title: String
        var columns: [Column]
        /// Loads the rows; nil when it would need a permission the user wasn't asked for yet.
        var load: () async throws -> [Row]?
        /// The button that asks for the permission and loads.
        var askTitle: String
        var ask: () async throws -> [Row]
        /// What the tab says when nothing was found.
        var emptyText: String
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
        /// The search's tab title when there are tabs.
        var searchTitle = "Search pages"
        /// A "Browse pages" tab (upstream `ConfluenceTreePickerPage`).
        var browse: UploadPickerBrowser.Configuration? = nil
        /// An "Open pages" tab (upstream `ConfluencePagePickerPage`).
        var openRows: OpenRows? = nil
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
    private var openTask: Task<Void, Never>?
    private var accepted = false
    private let tabs = NSTabView()
    /// The tab buttons (a segmented control above a tabless tab view, like Mac settings panes).
    private let tabButtons = NSSegmentedControl()
    private var browser: UploadPickerBrowser?
    private var openList: UploadPickerList?
    /// The user changed the tab: loading open rows doesn't switch it any more.
    private var userChoseTab = false
    private var switchingTab = false

    init(_ configuration: Configuration) {
        self.configuration = configuration
        let width = max(540, configuration.columns.reduce(0) { $0 + $1.width } + 150)
        let hasTabs = configuration.browse != nil || configuration.openRows != nil
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: hasTabs ? 540 : 480),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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
        loadOpenRows()
        NSApp.runModal(for: window)
        searchTask?.cancel()
        scopeTask?.cancel()
        openTask?.cancel()
        window.orderOut(nil)
        guard accepted else { return nil }
        return Choice(row: selectedRow, typedKey: keyField.stringValue, filename: filenameField.stringValue,
                      comment: commentField.stringValue, fromOpenRows: currentTab == "open")
    }

    /// The identifier of the tab shown: "open", "search" or "browse" ("search" without tabs).
    private var currentTab: String {
        (tabs.selectedTabViewItem?.identifier as? String) ?? "search"
    }

    /// The row picked in the tab shown.
    private var selectedRow: Row? {
        switch currentTab {
        case "open": return openList?.selectedRow
        case "browse": return browser?.selectedRow
        default: return table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil
        }
    }

    /// Shows rows and scopes without a server, for the snapshots.
    func preview(rows: [Row], scopes: [Scope], selectedScope: String?, icons: [URL: NSImage] = [:]) {
        self.icons = icons
        fillScopes(scopes, select: selectedScope)
        show(rows: rows, status: "\(rows.count) found")
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    /// Shows the browse tab with a tree, for the snapshots.
    func previewBrowse(_ nodes: [UploadPickerBrowser.Node], expand: [UploadPickerBrowser.Node], select: UploadPickerBrowser.Node?) {
        browser?.preview(nodes, expand: expand, select: select)
        tabs.selectTabViewItem(withIdentifier: "browse")
    }

    /// Shows the open-rows tab, for the snapshots: the rows, or the button that asks when `rows` is nil.
    func previewOpenRows(_ rows: [Row]?) {
        tabs.selectTabViewItem(withIdentifier: "open")
        guard let openRows = configuration.openRows, let list = openList else { return }
        if let rows {
            list.setAction(nil, nil)
            list.show(rows, status: rows.isEmpty ? openRows.emptyText : "\(rows.count) found")
        } else {
            list.setAction(openRows.askTitle) {}
            list.show([], status: Self.askText)
        }
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
        var searchRows: [[NSView]] = []
        if let scopeLabel = configuration.scopeLabel {
            scopePopup.addItem(withTitle: configuration.noScopeTitle)
            scopePopup.target = self
            scopePopup.action = #selector(scopeChosen)
            searchRows.append([label("\(scopeLabel):"), scopePopup])
        }
        searchField.placeholderString = configuration.searchPlaceholder
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(search)
        searchRows.append([label("Search:"), searchField])

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
        searchRows.append([label(""), scroll])
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.stringValue = configuration.recent.isEmpty ? "" : "Recent"
        searchRows.append([label(""), status])
        var tabsView: NSView?
        if configuration.browse == nil && configuration.openRows == nil {
            gridRows += searchRows
        } else {
            let view = tabView(searchRows: searchRows)
            tabsView = view
            gridRows.append([label(""), view])
        }

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
        if let tabsView { grid.cell(for: tabsView)?.xPlacement = .fill }
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
        let label = NSTextField(labelWithString: text)
        // The label column is as wide as its longest label; the fields take the rest.
        label.setContentHuggingPriority(.init(751), for: .horizontal)
        return label
    }

    /// The tabs "Open pages", "Search pages" and "Browse pages" (upstream `ConfluenceUploadWindow`).
    private func tabView(searchRows: [[NSView]]) -> NSView {
        func item(_ identifier: String, _ title: String, _ content: NSView) -> NSTabViewItem {
            let item = NSTabViewItem(identifier: identifier)
            item.label = title
            let holder = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12),
                content.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -12),
                content.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
                content.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12),
            ])
            item.view = holder
            return item
        }
        if let openRows = configuration.openRows {
            let list = UploadPickerList(columns: openRows.columns)
            list.selectionChanged = { [weak self] in self?.updateUploadButton() }
            list.doubleClicked = { [weak self] in self?.accept() }
            openList = list
            tabs.addTabViewItem(item("open", openRows.title, list.view))
        }
        // The search rows as full-width lines: "Space:" and "Search:" before their controls, the list and the status under them.
        let searchStack = NSStackView()
        searchStack.orientation = .vertical
        searchStack.alignment = .leading
        searchStack.spacing = 8
        for row in searchRows {
            let line: NSView
            if let label = row.first as? NSTextField, !label.stringValue.isEmpty, row.count > 1 {
                let pair = NSStackView(views: [label, row[1]])
                pair.orientation = .horizontal
                pair.spacing = 8
                line = pair
            } else {
                line = row.last ?? NSView()
            }
            searchStack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: searchStack.widthAnchor).isActive = true
        }
        tabs.addTabViewItem(item("search", configuration.searchTitle, searchStack))
        if let browse = configuration.browse {
            let tree = UploadPickerBrowser(browse)
            tree.selectionChanged = { [weak self] in self?.updateUploadButton() }
            tree.doubleClicked = { [weak self] in self?.accept() }
            browser = tree
            tabs.addTabViewItem(item("browse", "Browse pages", tree.view))
        }
        tabs.tabViewType = .noTabsBezelBorder
        tabs.selectTabViewItem(withIdentifier: "search")
        tabs.delegate = self
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        tabButtons.segmentCount = tabs.numberOfTabViewItems
        for (index, item) in tabs.tabViewItems.enumerated() {
            tabButtons.setLabel(item.label, forSegment: index)
        }
        tabButtons.trackingMode = .selectOne
        tabButtons.target = self
        tabButtons.action = #selector(tabButtonChosen)
        tabButtons.selectedSegment = tabs.indexOfTabViewItem(withIdentifier: "search")
        let stack = NSStackView(views: [tabButtons, tabs])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        tabs.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        // Wide like the fields below it, not as narrow as its content.
        stack.setContentHuggingPriority(.init(1), for: .horizontal)
        // NSGridView gives spare width to the label column: the tabs ask for the window's width less the labels.
        let windowWidth = max(540, configuration.columns.reduce(0) { $0 + $1.width } + 150)
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: windowWidth - 130).isActive = true
        return stack
    }

    @objc private func tabButtonChosen() {
        tabs.selectTabViewItem(at: tabButtons.selectedSegment)
    }

    static let askText = "Greenshot can read the addresses of the pages open in Safari and Chrome. macOS asks once per browser whether to allow it."

    /// Fills the open-rows tab when it can without asking; selects it when it found rows and the user didn't switch.
    private func loadOpenRows() {
        guard let openRows = configuration.openRows, let list = openList else { return }
        list.show([], status: "Looking…")
        openTask = Task { @MainActor [weak self] in
            do {
                let found = try await openRows.load()
                guard !Task.isCancelled, let self else { return }
                if let found {
                    list.setAction(nil, nil)
                    list.show(found, status: found.isEmpty ? openRows.emptyText : "\(found.count) found")
                    if !found.isEmpty, !userChoseTab { select("open") }
                } else {
                    list.show([], status: Self.askText)
                    list.setAction(openRows.askTitle) { [weak self] in self?.askOpenRows() }
                }
            } catch {
                guard !Task.isCancelled else { return }
                list.show([], status: Uploads.explained(error).localizedDescription)
            }
        }
    }

    private func askOpenRows() {
        guard let openRows = configuration.openRows, let list = openList else { return }
        list.setAction(nil, nil)
        list.show([], status: "Looking…")
        openTask = Task { @MainActor in
            do {
                let found = try await openRows.ask()
                guard !Task.isCancelled else { return }
                list.show(found, status: found.isEmpty ? openRows.emptyText : "\(found.count) found")
            } catch {
                guard !Task.isCancelled else { return }
                list.show([], status: error.localizedDescription)
            }
        }
    }

    private func select(_ identifier: String) {
        switchingTab = true
        tabs.selectTabViewItem(withIdentifier: identifier)
        switchingTab = false
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
        uploadButton.isEnabled = selectedRow != nil || (configuration.keyLabel != nil && configuration.acceptsKey(keyField.stringValue))
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

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if let tabViewItem { tabButtons.selectedSegment = tabView.indexOfTabViewItem(tabViewItem) }
        if !switchingTab { userChoseTab = true }
        if (tabViewItem?.identifier as? String) == "browse" { browser?.start() }
        updateUploadButton()
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

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Uploads")

/// The "Browse pages" tab of the Confluence dialog: port of upstream `ConfluenceTreePickerPage` (spaces, their home
/// pages and the child pages, loaded when a node is opened).
@MainActor
final class UploadPickerBrowser: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// One entry of the tree: a space (not pickable) or a page (`row`).
    class Node {
        let id: String
        let title: String
        /// The row a picked page gives back; nil for a space.
        let row: UploadPickerPanel.Row?
        /// nil until loaded.
        var children: [Node]?
        let mayHaveChildren: Bool
        var loading = false

        init(id: String, title: String, row: UploadPickerPanel.Row?, mayHaveChildren: Bool = true, children: [Node]? = nil) {
            self.id = id
            self.title = title
            self.row = row
            self.mayHaveChildren = mayHaveChildren
            self.children = children
        }
    }

    struct Configuration {
        var loadRoots: () async throws -> [Node]
        var loadChildren: (Node) async throws -> [Node]
    }

    let view = NSView()
    var selectionChanged: () -> Void = {}
    var doubleClicked: () -> Void = {}
    private let configuration: Configuration
    private let outline = NSOutlineView()
    private let status = NSTextField(labelWithString: "")
    private var roots: [Node] = []
    private var started = false

    init(_ configuration: Configuration) {
        self.configuration = configuration
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "Page"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClick)
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = true
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [scroll, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    /// The picked page, if a page (not a space) is selected.
    var selectedRow: UploadPickerPanel.Row? {
        (outline.item(atRow: outline.selectedRow) as? Node)?.row
    }

    /// Loads the spaces the first time the tab is shown.
    func start() {
        guard !started else { return }
        started = true
        status.stringValue = "Loading the spaces…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                roots = try await configuration.loadRoots()
                outline.reloadData()
                status.stringValue = roots.isEmpty ? "No spaces" : "\(roots.count) spaces"
            } catch {
                log.error("Loading the spaces failed", error: error)
                status.stringValue = Uploads.explained(error).localizedDescription
            }
        }
    }

    /// Shows a tree without a server, for the snapshots.
    func preview(_ nodes: [Node], expand: [Node], select: Node?) {
        started = true
        roots = nodes
        outline.reloadData()
        expand.forEach { outline.expandItem($0) }
        if let select {
            let row = outline.row(forItem: select)
            if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
        }
        status.stringValue = "\(nodes.count) spaces"
    }

    @objc private func doubleClick() {
        guard let node = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if node.row != nil {
            doubleClicked()
        } else if outline.isItemExpanded(node) {
            outline.collapseItem(node)
        } else {
            outline.expandItem(node)
        }
    }

    private func load(_ node: Node) {
        guard node.children == nil, !node.loading else { return }
        node.loading = true
        status.stringValue = "Loading \(node.title)…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                node.children = try await configuration.loadChildren(node)
                status.stringValue = ""
            } catch {
                log.error("Loading the pages of \(node.title) failed", error: error)
                node.children = []
                status.stringValue = Uploads.explained(error).localizedDescription
            }
            node.loading = false
            outline.reloadItem(node, reloadChildren: true)
            if node.children?.isEmpty == false { outline.expandItem(node) }
        }
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return roots.count }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node else { return roots[index] }
        return node.children?[index] ?? node
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return node.children.map { !$0.isEmpty } ?? node.mayHaveChildren
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        if node.children == nil {
            load(node)
            return false
        }
        return true
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("node")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier)
        cell.textField?.stringValue = node.loading ? "\(node.title) …" : node.title
        cell.imageView?.image = NSImage(systemSymbolName: node.row == nil ? "square.stack.3d.up" : "doc.text",
                                        accessibilityDescription: nil)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        selectionChanged()
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let image = NSImageView()
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        for view in [image, field] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = field
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A plain list of rows with columns, no sorting: the "Open pages" tab (upstream `ConfluencePagePickerPage`).
@MainActor
final class UploadPickerList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    var selectionChanged: () -> Void = {}
    var doubleClicked: () -> Void = {}
    private(set) var rows: [UploadPickerPanel.Row] = []
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var action: (() -> Void)?

    init(columns: [UploadPickerPanel.Column]) {
        super.init()
        for (index, column) in columns.enumerated() {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            tableColumn.title = column.title
            tableColumn.width = column.width
            table.addTableColumn(tableColumn)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.target = self
        table.doubleAction = #selector(doubleClick)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        actionButton.target = self
        actionButton.action = #selector(runAction)
        actionButton.isHidden = true
        let stack = NSStackView(views: [scroll, status, actionButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
    }

    var selectedRow: UploadPickerPanel.Row? {
        table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil
    }

    func show(_ rows: [UploadPickerPanel.Row], status text: String) {
        self.rows = rows
        table.reloadData()
        status.stringValue = text
        if rows.count == 1 { table.selectRowIndexes([0], byExtendingSelection: false) }
        selectionChanged()
    }

    /// A button under the list (e.g. "Look in Safari and Chrome"); nil hides it.
    func setAction(_ title: String?, _ action: (() -> Void)?) {
        actionButton.title = title ?? ""
        actionButton.isHidden = title == nil
        self.action = action
    }

    @objc private func runAction() {
        action?()
    }

    @objc private func doubleClick() {
        if selectedRow != nil { doubleClicked() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let index = Int(tableColumn.identifier.rawValue.dropFirst()), row < rows.count else { return nil }
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
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let values = rows[row].values
        cell.textField?.stringValue = index < values.count ? values[index] : ""
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionChanged()
    }
}

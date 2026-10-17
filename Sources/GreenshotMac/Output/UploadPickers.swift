// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Jira issue list of the upload dialog: port of upstream `Greenshot.Plugin.Jira/Views/JiraUploadWindow.xaml`
/// (a favourite filter, then the columns type, key, created, assignee, reporter and summary).
enum JiraPicker {
    static let columns = [
        UploadPickerPanel.Column(title: "Type", width: 100, showsIcon: true),
        UploadPickerPanel.Column(title: "Key", width: 90),
        UploadPickerPanel.Column(title: "Created", width: 90),
        UploadPickerPanel.Column(title: "Assignee", width: 110),
        UploadPickerPanel.Column(title: "Reporter", width: 110),
        UploadPickerPanel.Column(title: "Summary", width: 260),
    ]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    static func row(_ issue: JiraIssue) -> UploadPickerPanel.Row {
        let created = issue.created.map(dateFormatter.string(from:)) ?? ""
        let sortCreated = issue.created.map { String(format: "%015.0f", $0.timeIntervalSince1970) } ?? ""
        let values = [issue.type ?? "", issue.key, created, issue.assignee ?? "", issue.reporter ?? "", issue.summary]
        var sortKeys = values
        sortKeys[2] = sortCreated
        return UploadPickerPanel.Row(id: issue.key, values: values, sortKeys: sortKeys,
                                     iconURL: issue.typeIconURL.map(JiraClient.pngIconURL))
    }

    static func recentRow(_ key: String) -> UploadPickerPanel.Row {
        UploadPickerPanel.Row(id: key, values: ["", key, "", "", "", ""])
    }

    static func configuration(client: JiraClient, settings: AppSettings, filename: String) -> UploadPickerPanel.Configuration {
        var filters: [String: JiraFilter] = [:]
        var configuration = UploadPickerPanel.Configuration(
            title: "Upload to Jira", keyLabel: "Issue key", searchPlaceholder: "Words in the summary, or JQL",
            columns: columns, recent: settings.jira.recentIssueKeys.map(recentRow), filename: filename, showsComment: true,
            acceptsKey: JiraClient.isIssueKey,
            search: { text, _ in try await client.search(text).map(row) })
        configuration.scopeLabel = "Filter"
        configuration.noScopeTitle = "Recent issues"
        configuration.loadScopes = {
            let found = try await client.favouriteFilters()
            for filter in found { filters[filter.id] = filter }
            return found.map { UploadPickerPanel.Scope(id: $0.id, title: $0.name) }
        }
        configuration.listScope = { scope in
            guard let filter = filters[scope.id] else { return [] }
            return try await client.search(jql: filter.jql).map(row)
        }
        configuration.loadIcon = { url in
            guard let data = try? await client.imageData(at: url), let image = NSImage(data: data) else { return nil }
            image.size = NSSize(width: 16, height: 16)
            return image
        }
        return configuration
    }
}

/// The Confluence page chooser of the upload dialog: upstream `ConfluenceUploadWindow` with its tabs "Open pages"
/// (`ConfluencePagePickerPage`), "Search pages" (`ConfluenceSearchPage`: a space, the title words; the recent pages
/// before a search) and "Browse pages" (`ConfluenceTreePickerPage`: spaces, home pages, child pages).
@MainActor
final class ConfluencePicker {
    struct Choice {
        var page: ConfluencePage
        var filename: String
        var comment: String
        /// The page is open in the browser already (upstream `IsOpenPageSelected`: it isn't opened again).
        var isOpenPage: Bool
    }

    private let panel: UploadPickerPanel
    private let found = FoundPages()
    private let recent: [ConfluencePage]

    /// `openPages` finds the pages open in the browsers: nil when that would need asking for a permission first
    /// (`ask: false`), see `BrowserPages`.
    init(client: ConfluenceClient, settings: SettingsStore, filename: String,
         openPages: ((_ ask: Bool) async throws -> [ConfluencePage]?)? = nil) {
        let s = settings.value
        recent = s.confluence.recentPages
        let found = self.found
        let includePersonal = s.confluence.includePersonalSpaces
        let columns = [UploadPickerPanel.Column(title: "Page", width: 260), UploadPickerPanel.Column(title: "Space", width: 180)]
        var configuration = UploadPickerPanel.Configuration(
            title: "Upload to Confluence", keyLabel: nil, searchPlaceholder: "Words in the page title, or CQL",
            columns: columns, recent: recent.map(Self.row), filename: filename, showsComment: true,
            search: { text, space in
                let result = try await client.searchPages(title: text, spaceKey: space?.id ?? "", includePersonalSpaces: includePersonal)
                found.pages += result
                return result.map(Self.row)
            })
        configuration.scopeLabel = "Space"
        configuration.noScopeTitle = "All spaces"
        configuration.initialScopeID = s.confluence.searchSpaceKey.isEmpty ? nil : s.confluence.searchSpaceKey
        configuration.loadScopes = {
            ConfluenceClient.filtered(try await client.spaces(), includePersonal: includePersonal)
                .map { UploadPickerPanel.Scope(id: $0.key, title: $0.name) }
        }
        // Upstream remembers the space of the last search (`SearchSpaceKey`).
        configuration.scopeChanged = { scope in settings.update { $0.confluence.searchSpaceKey = scope?.id ?? "" } }
        configuration.browse = Self.browse(client: client, includePersonal: includePersonal, found: found)
        if let openPages {
            configuration.openRows = UploadPickerPanel.OpenRows(
                title: "Open pages", columns: columns,
                load: {
                    guard let pages = try await openPages(false) else { return nil }
                    found.pages += pages
                    return pages.map(Self.row)
                },
                askTitle: "Look in Safari and Chrome",
                ask: {
                    let pages = try await openPages(true) ?? []
                    found.pages += pages
                    return pages.map(Self.row)
                },
                emptyText: "No page of this Confluence is open in Safari or Chrome.")
        }
        panel = UploadPickerPanel(configuration)
    }

    /// The tree: spaces, each with its home page, the pages with their children.
    private static func browse(client: ConfluenceClient, includePersonal: Bool, found: FoundPages) -> UploadPickerBrowser.Configuration {
        UploadPickerBrowser.Configuration(
            loadRoots: {
                ConfluenceClient.filtered(try await client.spaces(), includePersonal: includePersonal).map { space in
                    SpaceNode(space)
                }
            },
            loadChildren: { node in
                let pages: [ConfluencePage]
                if let space = node as? SpaceNode {
                    guard let homepage = space.space.homepageID else { return [] }
                    pages = [try await client.page(id: homepage, spaceName: space.space.name)]
                } else {
                    let spaceName = node.row?.values.last ?? ""
                    pages = try await client.childPages(of: node.id, spaceName: spaceName)
                }
                found.pages += pages
                return pages.map(pageNode)
            })
    }

    nonisolated static func row(_ page: ConfluencePage) -> UploadPickerPanel.Row {
        UploadPickerPanel.Row(id: page.id, values: [page.title, page.spaceName])
    }

    static func pageNode(_ page: ConfluencePage) -> UploadPickerBrowser.Node {
        UploadPickerBrowser.Node(id: page.id, title: page.title, row: row(page))
    }

    /// A space in the tree; its child is its home page.
    final class SpaceNode: UploadPickerBrowser.Node {
        let space: ConfluenceSpace

        init(_ space: ConfluenceSpace) {
            self.space = space
            super.init(id: "space:" + space.key, title: space.name, row: nil, mayHaveChildren: space.homepageID != nil)
        }
    }

    var contentView: NSView? { panel.contentView }

    func preview(pages: [ConfluencePage], spaces: [ConfluenceSpace], selected: String?) {
        panel.preview(rows: pages.map(Self.row), scopes: spaces.map { UploadPickerPanel.Scope(id: $0.key, title: $0.name) },
                      selectedScope: selected)
    }

    /// The browse tab with a tree, for the snapshots.
    func previewBrowse(spaces: [ConfluenceSpace], homepage: ConfluencePage, children: [ConfluencePage]) {
        let nodes = spaces.map(SpaceNode.init)
        guard let first = nodes.first else { return }
        let home = Self.pageNode(homepage)
        home.children = children.map(Self.pageNode)
        first.children = [home]
        panel.previewBrowse(nodes, expand: [first, home], select: home.children?.first)
    }

    /// The open pages tab, for the snapshots; nil shows the button that asks first.
    func previewOpenPages(_ pages: [ConfluencePage]?) {
        panel.previewOpenRows(pages?.map(Self.row))
    }

    func run() -> Choice? {
        guard let choice = panel.run(), let id = choice.row?.id,
              let page = (found.pages + recent).first(where: { $0.id == id }) else { return nil }
        return Choice(page: page, filename: choice.filename, comment: choice.comment, isOpenPage: choice.fromOpenRows)
    }

    /// The pages of the searches, the tree and the browsers, so the picked row can become a page again.
    private final class FoundPages: @unchecked Sendable {
        var pages: [ConfluencePage] = []
    }
}

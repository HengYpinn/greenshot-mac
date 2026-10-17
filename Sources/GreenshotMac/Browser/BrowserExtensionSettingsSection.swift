// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Expert › Browser extension: whether the extension may connect, which browsers know the app's native
/// messaging host (upstream registers it in its installer, `includes\browser-extension.iss`; here nothing is registered
/// until the user clicks Install), and the extension's folder for the browsers' "Load unpacked".
struct BrowserExtensionSettingsSection: View {
    @ObservedObject var store: SettingsStore
    /// Replaceable for the snapshots (a fixed home, host and browsers).
    var integration: BrowserIntegration
    @State private var rows: [BrowserIntegration.Row]
    @State private var message: String?

    /// `rows`: the browsers to show at first (the snapshots); nil reads them when the section appears.
    init(store: SettingsStore, integration: BrowserIntegration = .current, rows: [BrowserIntegration.Row]? = nil) {
        self.store = store
        self.integration = integration
        _rows = State(initialValue: rows ?? [])
        loadsRows = rows == nil
    }

    private let loadsRows: Bool

    var body: some View {
        Section {
            Toggle("Allow the browser extension to send screenshots", isOn: store.binding(\.browserExtensionEnabled))
                .managed(\.browserExtensionEnabled)
                .help("The Greenshot for Mac (Community) Companion extension for Chrome, Edge and Firefox sends the visible page and the page's address.")
            if rows.isEmpty {
                LabeledContent("Browsers") {
                    Text("None found (Chrome, Edge, Firefox, Brave, Vivaldi or Chromium)").foregroundStyle(.secondary)
                }
            } else {
                ForEach(rows) { row in
                    LabeledContent(row.browser.name) {
                        Text(Self.stateText(row.state))
                            .foregroundStyle(Self.isProblem(row.state) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .help(Self.stateHelp(row.state))
                    }
                }
            }
            HStack {
                Button("Install") { install() }
                    .disabled(!store.value.browserExtensionEnabled || integration.hostPath == nil || rows.isEmpty)
                    .help("Lets these browsers start Greenshot's connection for the extension (a file in each browser's NativeMessagingHosts folder).")
                Button("Remove") { remove() }
                    .disabled(!rows.contains { $0.state != .notInstalled })
                Spacer()
                Button("Show Extension Folder…") { revealExtension() }
                    .disabled(integration.extensionSource == nil)
                    .help("Copies the extension to Greenshot's folder in Application Support and shows it, for Load unpacked.")
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Browser extension")
        } footer: {
            Text("Chrome, Edge, Brave: open the Extensions page, turn on Developer mode, click Load unpacked and choose the extension folder. Firefox 126 or later: about:debugging › This Firefox › Load Temporary Add-on… and choose manifest.json in it. File names can then use ${url} and ${browser} of the page, and ${Browser.Url}, ${Browser.Domain}, ${Browser.Title}, ${Browser.Ticket} of the browser's active tab (the extension's tab tracking).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if loadsRows { refresh() } }
    }

    private func refresh() {
        rows = integration.rows()
    }

    private func install() {
        let failed = integration.installAll()
        message = failed.isEmpty ? nil : "Couldn't register the extension's connection for \(failed.joined(separator: ", ")); see the log."
        refresh()
    }

    private func remove() {
        let failed = integration.removeAll()
        message = failed.isEmpty ? nil : "Couldn't remove the registration for \(failed.joined(separator: ", ")); see the log."
        refresh()
    }

    private func revealExtension() {
        do {
            _ = try integration.revealExtensionFolder()
            message = nil
        } catch {
            message = "The extension folder couldn't be copied: \(error.localizedDescription)"
        }
    }

    static func stateText(_ state: BrowserHostManifest.State) -> String {
        switch state {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed"
        case .otherCopy: return "Installed for another copy of the app"
        case .stale: return "Points to a missing app: click Install"
        case .unreadable: return "Unreadable registration: click Install"
        }
    }

    static func isProblem(_ state: BrowserHostManifest.State) -> Bool {
        switch state {
        case .stale, .unreadable, .otherCopy: return true
        case .notInstalled, .installed: return false
        }
    }

    static func stateHelp(_ state: BrowserHostManifest.State) -> String {
        switch state {
        case .otherCopy(let path), .stale(let path): return DiagnosticReport.abbreviatingHome(path)
        default: return ""
        }
    }
}

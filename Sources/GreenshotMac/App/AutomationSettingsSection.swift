// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Expert › Automation: whether links may take screenshots (Mac only; upstream lets a link start only the
/// recipes that allow browser invocation) and where the command line tool is, with the command that puts it on the PATH.
struct AutomationSettingsSection: View {
    @ObservedObject var store: SettingsStore
    /// The tool's path; nil when it isn't next to the app (a bare `swift build`). Replaceable for the snapshots.
    var toolPath: String? = AutomationSettingsSection.installedToolPath
    @State private var copied = false

    var body: some View {
        Section {
            Toggle("Allow links to take screenshots", isOn: store.binding(\.automationAllowCaptureLinks))
                .managed(\.automationAllowCaptureLinks)
                .help("greenshotmac://capture/region, …/window, …/fullscreen, …/last, …/text and greenshotmac://clipboard, e.g. from Alfred, Raycast or a web page.")
            LabeledContent("Command line tool") {
                if let toolPath {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(DiagnosticReport.abbreviatingHome(toolPath))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        Button(copied ? "Copied" : "Copy Install Command") { copyInstallCommand(toolPath) }
                            .help("Copies a Terminal command that links greenshot-cli into /usr/local/bin.")
                    }
                } else {
                    Text("Not found next to the app").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Automation")
        } footer: {
            Text("Links like greenshotmac://settings?tab=editor open windows; any web page can open a link, so links take screenshots only when allowed here. greenshot-cli, AppleScript, Shortcuts and the Services menu can always capture.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func copyInstallCommand(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand(for: path), forType: .string)
        copied = true
    }

    static func installCommand(for path: String) -> String {
        "sudo ln -sf '\(path.replacingOccurrences(of: "'", with: "'\\''"))' /usr/local/bin/greenshot-cli"
    }

    /// `Contents/Helpers/greenshot-cli` of the app bundle, or `greenshot-cli` next to a bare build.
    static var installedToolPath: String? {
        let executable = IPCEndpoint.currentExecutablePath
        let path: String
        if let bundle = IPCPeerPolicy.appBundle(ofExecutable: executable) {
            path = (bundle as NSString).appendingPathComponent("Contents/Helpers/greenshot-cli")
        } else {
            path = ((executable as NSString).deletingLastPathComponent as NSString).appendingPathComponent("greenshot-cli")
        }
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

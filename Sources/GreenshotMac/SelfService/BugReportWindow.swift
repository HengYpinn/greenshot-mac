// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The bug report: port of upstream `Greenshot/ViewModels/BugReportViewModel.cs` and `Views/BugReportWindow.xaml`.
/// The error with an identifier (a hash of its stack, the same for the same error), a search for issues with it, a
/// new issue with it, the stack and the whole report to copy, and whether a newer version is out.
@MainActor
final class BugReportModel: ObservableObject {
    let details: CrashDetails
    let report: String
    let hash: String
    let environmentSummary: String

    enum VersionState: Equatable {
        case checking
        case known(UpdateCheck.Outcome)
    }

    @Published var version = VersionState.checking
    @Published var showsDetails = false
    @Published var copyDetailsTitle = "Copy Details"
    @Published var copyStackTitle = "Copy Stack Trace"

    init(details: CrashDetails, environment: EnvironmentSnapshot, settings: AppSettings) {
        self.details = details
        report = DiagnosticReport.bugReport(environment: environment, crash: details, settings: settings)
        hash = IssueLinks.hash(of: details)
        environmentSummary = DiagnosticReport.environmentText(environment, newline: true)
            .split(separator: "\n").prefix(4).joined(separator: "\n")
    }

    var installedVersion: String {
        "\(UpdateChecker.currentVersion) (\(AppAboutCredits.versionDetail))"
    }

    var latestVersion: String {
        switch version {
        case .checking: return "Checking…"
        case .known(.newer(let release)): return release.version
        case .known(.upToDate(let latest)): return latest ?? UpdateChecker.currentVersion
        case .known(.failed): return "Unavailable"
        }
    }

    /// Upstream `VersionComparisonText`.
    var versionComparison: String? {
        switch version {
        case .known(.newer(let release)):
            return "A newer version (\(release.version)) is available. Upgrading may already solve this problem!"
        case .known(.upToDate):
            return "You are using the latest version (\(UpdateChecker.currentVersion))."
        default:
            return nil
        }
    }

    var newerRelease: UpdateCheck.Release? {
        if case .known(.newer(let release)) = version { return release }
        return nil
    }

    var title: String {
        details.kind == .crashReport || details.kind == .uncaughtException
            ? "\(AppInfo.name) quit unexpectedly the last time" : "Something went wrong"
    }

    var subtitle: String {
        switch details.kind {
        case .caughtException:
            return "\(AppInfo.name) ran into an error, but it is still running. You can check whether the problem was reported already, or report it with the details below."
        case .uncaughtException, .crashReport:
            return "\(AppInfo.name) ended because of an error the last time it ran. You can check whether the problem was reported already, or report it with the details below."
        }
    }

    func checkVersion(unstable: Bool) {
        Task { @MainActor in
            version = .known(await UpdateChecker.fetchLatest(unstable: unstable))
        }
    }

    func searchIssues() {
        NSWorkspace.shared.open(IssueLinks.searchURL(hash: hash))
    }

    func reportIssue() {
        NSWorkspace.shared.open(IssueLinks.newIssueURL(hash: hash, type: details.type, environment: environmentSummary))
    }

    func copyDetails() {
        copy(report)
        copyDetailsTitle = "Copied!"
    }

    func copyStack() {
        copy(details.stackText)
        copyStackTitle = "Copied!"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct BugReportView: View {
    @ObservedObject var model: BugReportModel
    var openSelfService: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content.padding(20)
            }
            Divider()
            HStack {
                Button("Self-Service…", action: openSelfService)
                    .help("Check the setup, the log and the system of \(AppInfo.name)")
                Spacer()
                Button("Report on GitHub…") { model.reportIssue() }
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title).font(.title2.weight(.semibold))
                    Text(model.subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            versionBox
            identifierBox
            VStack(alignment: .leading, spacing: 4) {
                Text("Error message").font(.headline)
                Text(model.details.message.isEmpty ? "An unexpected error occurred." : model.details.message)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Stack trace").font(.headline)
                    Spacer()
                    Button(model.copyStackTitle) { model.copyStack() }.controlSize(.small)
                }
                ScrollView {
                    Text(model.details.stackText.isEmpty ? "(no stack)" : model.details.stackText)
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            }
            DisclosureGroup(isExpanded: $model.showsDetails) {
                VStack(alignment: .trailing, spacing: 6) {
                    ScrollView {
                        Text(model.report).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    .frame(height: 160)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                    Button(model.copyDetailsTitle) { model.copyDetails() }.controlSize(.small)
                }
            } label: {
                HStack {
                    Text("Details for the report").font(.headline)
                    Spacer()
                    if !model.showsDetails { Button(model.copyDetailsTitle) { model.copyDetails() }.controlSize(.small) }
                }
            }
        }
    }

    private var versionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Installed version:").foregroundStyle(.secondary)
                Text(model.installedVersion)
                Text("|").foregroundStyle(.tertiary)
                Text("Latest release:").foregroundStyle(.secondary)
                Text(model.latestVersion)
            }
            .font(.callout)
            if let comparison = model.versionComparison {
                HStack {
                    Text(comparison).font(.callout)
                        .foregroundStyle(model.newerRelease == nil ? Color.secondary : Color.orange)
                    Spacer()
                    if let release = model.newerRelease {
                        Button("Download Update") { NSWorkspace.shared.open(release.pageURL) }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
    }

    private var identifierBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Issue identifier (stack trace hash)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(model.hash.isEmpty ? "[No Stack]" : "[\(model.hash)]")
                    .font(.system(.body, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                Text(model.details.type).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Search Existing Issues") { model.searchIssues() }
            }
            Text("Searching GitHub for this identifier helps avoid filing the same issue twice and shows whether a fix or a workaround is known.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }
}

/// One bug report at a time (upstream shows one per error; a second error while one is open is only logged here, so
/// an error in a loop can't open window after window).
@MainActor
final class BugReportWindowController: DiagnosticsWindowController {
    private static var current: BugReportWindowController?
    private static let log = Log("Crash")

    init(model: BugReportModel) {
        var close: () -> Void = {}
        let view = BugReportView(model: model, openSelfService: {
            (NSApp.delegate as? AppDelegate)?.showSelfService(section: nil)
        }, close: { close() })
        super.init(title: "\(AppInfo.name) – Error Report", content: view, size: NSSize(width: 660, height: 700),
                   resizable: true)
        close = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    static func show(_ details: CrashDetails) {
        if let current, current.isOpen {
            log.info("Another error while the error report is open: \(details.type)")
            return
        }
        let app = NSApp.delegate as? AppDelegate
        let settings = app?.settings.value ?? AppSettings()
        let model = BugReportModel(details: details, environment: SystemInfo.snapshot(), settings: settings)
        model.checkVersion(unstable: settings.checkForUnstable)
        let controller = BugReportWindowController(model: model)
        current = controller
        controller.present()
    }

    override func didClose() {
        if Self.current === self { Self.current = nil }
    }
}

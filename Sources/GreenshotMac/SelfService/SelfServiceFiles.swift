// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Self-Service › Files and Log: port of upstream `FileInfoSectionViewModel.cs`. The settings file and the log with
/// their paths, sizes and dates, Copy Path, Show in Finder, the end of the log at a glance and the log viewer, and the
/// crash reports macOS kept of the app.
@MainActor
final class FilesSectionModel: ObservableObject {
    struct FileInfo: Equatable {
        var url: URL
        var exists: Bool
        var size: String
        var modified: String

        var path: String { (url.path as NSString).abbreviatingWithTildeInPath }
    }

    @Published private(set) var settingsFile: FileInfo
    @Published private(set) var settingsInUserDefaults: Bool
    @Published private(set) var logFile: FileInfo
    @Published private(set) var glance = ""
    @Published private(set) var crashReports = 0
    private weak var app: AppDelegate?
    private let live: Bool

    init(app: AppDelegate) {
        self.app = app
        live = true
        let (url, defaults) = Self.settingsLocation()
        settingsFile = Self.info(url)
        settingsInUserDefaults = defaults
        logFile = Self.info(LogCenter.fileURL ?? AppInfo.logFile)
        refresh()
    }

    /// Fixed values (snapshots).
    init(settingsFile: FileInfo, logFile: FileInfo, glance: String, crashReports: Int) {
        live = false
        self.settingsFile = settingsFile
        settingsInUserDefaults = true
        self.logFile = logFile
        self.glance = glance
        self.crashReports = crashReports
    }

    /// `settings.json` of `--settings-dir`, else the user defaults' file (named after the bundle identifier, or after
    /// the executable for a bare `swift build`).
    static func settingsLocation() -> (URL, inUserDefaults: Bool) {
        let options = AppLaunchOptions.parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        if let file = options.settingsFile { return (file, false) }
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist")
        return (url, true)
    }

    func refresh() {
        guard live else { return }
        settingsFile = Self.info(settingsFile.url)
        logFile = Self.info(LogCenter.fileURL ?? AppInfo.logFile)
        glance = Self.glance(of: logFile)
        crashReports = CrashReporting.crashReportCount()
    }

    static func info(_ url: URL) -> FileInfo {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let exists = FileManager.default.fileExists(atPath: url.path)
        return FileInfo(url: url, exists: exists,
                        size: exists ? DiagnosticReport.byteCount(UInt64(values?.fileSize ?? 0)) : String(localized: "File not found"),
                        modified: values?.contentModificationDate.map(LogViewerModel.dateTime) ?? "–")
    }

    /// The last 16 KB of the log (upstream `LoadRecentLog`).
    static func glance(of file: FileInfo) -> String {
        guard file.exists else { return String(localized: "Log file does not currently exist at: \(file.path)") }
        guard let chunk = try? LogFile.readTail(file.url, bytes: 16 * 1024) else { return String(localized: "The log file could not be read.") }
        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "(Log file is empty)") : LogSanitizer.escapeUnsafeCharacters(text)
    }

    func copyPath(_ file: FileInfo) {
        // Through Clipboard: the write is recorded as Greenshot's own (recipe Clipboard triggers ignore it).
        Clipboard.copy(text: file.url.path)
    }

    /// The file in Finder, or its folder when it isn't there.
    func reveal(_ file: FileInfo) {
        if file.exists {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } else {
            NSWorkspace.shared.open(file.url.deletingLastPathComponent())
        }
    }

    func openLogViewer() {
        app?.showLogViewer(search: nil)
    }

    func openCrashReports() {
        NSWorkspace.shared.open(CrashReporting.reportsFolder)
    }
}

struct FilesSectionView: View {
    @ObservedObject var model: FilesSectionModel
    var status: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            file(title: model.settingsInUserDefaults ? String(localized: "Settings (in the user defaults)")
                                                     : String(localized: "Settings file (--settings-dir)"),
                 model.settingsFile)
            file(title: String(localized: "Log file (\(LogFile.fileName))"), model.logFile)
            SectionCard(title: String(localized: "The log at a glance")) {
                ReportText(text: model.glance, height: 160)
                HStack {
                    Text("Search, follow and copy the whole log in the log viewer.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Log Viewer") {
                        model.openLogViewer()
                        status(String(localized: "Opened the log viewer."))
                    }
                }
            }
            SectionCard(title: String(localized: "Crash reports")) {
                Text(crashReportsText)
                HStack {
                    Spacer()
                    Button("Show in Finder") { model.openCrashReports() }
                }
            }
        }
    }

    private var crashReportsText: String {
        let count = model.crashReports
        if count == 0 { return String(localized: "macOS has no crash report of \(AppInfo.name).") }
        return count == 1 ? String(localized: "macOS kept 1 crash report of \(AppInfo.name) in ~/Library/Logs/DiagnosticReports.")
            : String(localized: "macOS kept \(count) crash reports of \(AppInfo.name) in ~/Library/Logs/DiagnosticReports.")
    }

    private func file(title: String, _ info: FilesSectionModel.FileInfo) -> some View {
        SectionCard(title: title) {
            InfoRow(label: String(localized: "Path", comment: "The path of a file"), value: info.path)
            InfoRow(label: String(localized: "Size", comment: "The size of a file"), value: info.size)
            InfoRow(label: String(localized: "Changed", comment: "When a file was changed last"), value: info.modified)
            HStack {
                Spacer()
                Button("Copy Path") {
                    model.copyPath(info)
                    status(String(localized: "Copied the path."))
                }
                Button("Show in Finder") { model.reveal(info) }
            }
        }
    }
}

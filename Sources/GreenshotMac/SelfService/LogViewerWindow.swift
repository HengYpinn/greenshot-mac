// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// The log viewer: port of upstream `Greenshot/SelfService/Views/LogViewerWindow.xaml(.cs)`. The end of the log, 64 KB at
/// a time with "Load Earlier" and "Load Entire Log"; a search shows only the entries with the text, from the whole
/// file; the level of the log until the app quits; the entries written while it is open are added (every 250 ms).
@MainActor
final class LogViewerModel: ObservableObject {
    let fileURL: URL?
    /// Adds the entries the app writes while the window is open (only for the app's own log).
    let followsLog: Bool

    @Published private(set) var text = ""
    /// Changes when the text is replaced rather than extended.
    @Published private(set) var generation = 0
    @Published private(set) var scrollTarget = LogScrollTarget.end
    @Published private(set) var info = ""
    @Published private(set) var chunkStatus = ""
    @Published var status = ""
    @Published private(set) var canLoadEarlier = false
    @Published var wrap = false
    @Published var search = "" {
        didSet {
            guard search != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var level = LogCenter.level

    weak var searchField: NSSearchField?
    private var startOffset = 0
    private var fileLength = 0
    private var matchCount = 0
    private var entryCount = 0
    private var searchTimer: Timer?
    private var liveTimer: Timer?
    private var liveTail: LogLiveTail?
    private let log = Log("LogViewer")

    init(fileURL: URL?, followsLog: Bool, search: String = "") {
        self.fileURL = fileURL
        self.followsLog = followsLog
        self.search = search
    }

    var path: String {
        fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
    }

    // MARK: Loading

    /// The end of the log, or the search result when there is a search text (upstream `LoadLog`).
    func load() {
        if !search.isEmpty, fileExists { applySearch() } else { loadTail() }
    }

    private var fileExists: Bool {
        fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private var lastModified: String {
        guard let url = fileURL,
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return "?" }
        return Self.dateTime(date)
    }

    /// Shows the entries with the search text from the whole file, or the end of the log without one.
    func applySearch() {
        searchTimer?.invalidate()
        guard !search.isEmpty, let url = fileURL, fileExists else {
            loadTail()
            return
        }
        do {
            let whole = try LogFile.readAll(url)
            // The entries collected until now are in the file.
            _ = liveTail?.take()
            let result = LogSearch.filter(whole, search: search)
            matchCount = result.matchCount
            entryCount = result.entryCount
            fileLength = whole.utf8.count
            startOffset = 0
            canLoadEarlier = false
            chunkStatus = ""
            replace(text: result.text, scroll: .end)
            info = LogSearch.matchesText(result, search: search)
            status = "Searched at \(Self.time(Date())) | Last modified: \(lastModified)"
        } catch {
            log.error("Error searching the log file", error: error)
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func loadTail() {
        guard let url = fileURL, fileExists else {
            replace(text: "Log file does not currently exist at:\n\(path)", scroll: .end)
            info = "File not found"
            status = info
            chunkStatus = ""
            canLoadEarlier = false
            startOffset = 0
            fileLength = 0
            return
        }
        do {
            let chunk = try LogFile.readTail(url)
            _ = liveTail?.take()
            fileLength = chunk.fileLength
            startOffset = chunk.startOffset
            canLoadEarlier = chunk.hasEarlier
            if chunk.fileLength == 0 {
                replace(text: "(Log file is empty)", scroll: .end)
                info = "Size: 0 KB | 0 lines"
                chunkStatus = ""
                status = "Empty log file | Last modified: \(lastModified)"
                return
            }
            let shown = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No log entries in chunk)" : chunk.text
            replace(text: shown, scroll: .end)
            updateMetrics()
        } catch {
            log.error("Error reading the log file", error: error)
            replace(text: "Error reading log file:\n\(error.localizedDescription)", scroll: .end)
            info = "Read error"
            status = "Error: \(error.localizedDescription)"
            chunkStatus = ""
            canLoadEarlier = false
        }
    }

    /// The 64 KB before the shown part (upstream `LoadEarlierLines`), or all of it.
    func loadEarlier(all: Bool = false) {
        guard startOffset > 0, let url = fileURL, fileExists else {
            canLoadEarlier = false
            return
        }
        do {
            let chunk = try LogFile.readEarlier(url, before: startOffset, bytes: all ? nil : LogFile.chunkBytes)
            startOffset = chunk.startOffset
            canLoadEarlier = chunk.hasEarlier
            let earlier = LogSanitizer.escapeUnsafeCharacters(chunk.text)
            replace(text: earlier + text, scroll: .offset(earlier.utf16.count), escaped: true)
            updateMetrics()
            status = all ? "Complete log loaded at \(Self.time(Date()))" : "Loaded earlier chunk at \(Self.time(Date()))"
        } catch {
            log.error("Error loading earlier log entries", error: error)
            status = "Error loading earlier chunk: \(error.localizedDescription)"
        }
    }

    /// Replaces the shown text; the log of an older version can contain control characters, shown as `\uXXXX`.
    private func replace(text newText: String, scroll: LogScrollTarget, escaped: Bool = false) {
        text = escaped ? newText : LogSanitizer.escapeUnsafeCharacters(newText)
        scrollTarget = scroll
        generation += 1
    }

    private func updateMetrics() {
        let lines = text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        let total = Self.size(fileLength)
        let loaded = Self.size(max(0, fileLength - startOffset))
        if startOffset > 0 {
            info = "Showing ~\(LogSanitizer.groupedNumber(lines)) lines (\(loaded) of \(total))"
            chunkStatus = "Showing tail \(loaded) of \(total) total. Earlier log lines available."
        } else {
            info = "Complete log: ~\(LogSanitizer.groupedNumber(lines)) lines (\(total))"
            chunkStatus = "All \(total) loaded."
        }
        status = "Loaded at \(Self.time(Date())) | Last modified: \(lastModified)"
    }

    // MARK: Search, level, copy

    private func scheduleSearch() {
        searchTimer?.invalidate()
        // Search when the typing pauses, not for every key.
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySearch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        searchTimer = timer
    }

    func focusSearch() {
        guard let searchField else { return }
        searchField.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func setLevel(_ newLevel: LogLevel) {
        LogCenter.changeLevel(to: newLevel, note: "in the log viewer, until \(AppInfo.name) restarts")
        level = LogCenter.level
    }

    func copyLog() {
        guard !text.isEmpty else { return }
        // Through Clipboard: the write is recorded as Greenshot's own (recipe Clipboard triggers ignore it).
        Clipboard.copy(text: text)
        status = "Copied entire log content to clipboard (\(LogSanitizer.groupedNumber(text.count)) characters)"
    }

    // MARK: Live entries

    /// Collects what the app logs from now on and adds it every 250 ms (upstream `LogViewerAppender` and `OnLiveTick`).
    func startFollowing() {
        guard followsLog, liveTail == nil else { return }
        liveTail = LogCenter.beginLiveTail()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.liveTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    func stopFollowing() {
        liveTimer?.invalidate()
        liveTimer = nil
        searchTimer?.invalidate()
        liveTail?.end()
        liveTail = nil
    }

    private func liveTick() {
        guard let added = liveTail?.take(), !added.isEmpty else { return }
        if search.isEmpty {
            guard fileExists || fileURL == nil else { return }
            if text.hasPrefix("Log file does not currently exist") || text == "(Log file is empty)" {
                loadTail()
                return
            }
            text += LogSanitizer.escapeUnsafeCharacters(added)
            fileLength += added.utf8.count
            updateMetrics()
        } else {
            let result = LogSearch.filter(added, search: search)
            matchCount += result.matchCount
            entryCount += result.entryCount
            info = LogSearch.matchesText(LogSearch.Result(text: "", matchCount: matchCount, entryCount: entryCount), search: search)
            guard !result.text.isEmpty else { return }
            text += LogSanitizer.escapeUnsafeCharacters(result.text)
        }
    }

    // MARK: Formatting

    static func size(_ bytes: Int) -> String {
        bytes >= 1024 * 1024
            ? String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
            : String(format: "%.1f KB", Double(bytes) / 1024)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct LogViewerView: View {
    @ObservedObject var model: LogViewerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            HStack {
                Text(model.info).font(.callout.weight(.medium))
                Spacer()
                Text(model.chunkStatus).font(.caption).foregroundStyle(.secondary)
            }
            LogTextView(text: model.text, generation: model.generation, scrollTarget: model.scrollTarget, wrap: model.wrap)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Text(model.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 360)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            LogSearchField(text: $model.search, placeholder: "Search") { model.searchField = $0 }
                .frame(minWidth: 160, maxWidth: 260)
                .help("Shows only the log entries that contain this text, from the whole log file (⌘F)")
            Picker("Log level", selection: Binding(get: { model.level }, set: { model.setLevel($0) })) {
                ForEach(LogLevel.allCases.reversed(), id: \.self) { Text($0.name.capitalized).tag($0) }
            }
            .fixedSize()
            .help("How much \(AppInfo.name) writes to the log, until it restarts. Debug writes the most.")
            Toggle("Wrap text", isOn: $model.wrap)
            Spacer()
            Button("Load Earlier (+64 KB)") { model.loadEarlier() }
                .disabled(!model.canLoadEarlier)
                .help("Load the previous 64 KB of the log")
            Button("Load Entire Log") { model.loadEarlier(all: true) }
                .disabled(!model.canLoadEarlier)
            Button("Refresh") { model.load() }
                .keyboardShortcut("r", modifiers: .command)
                .help("Read the log again (F5, ⌘R)")
            Button("Copy Log") { model.copyLog() }
        }
    }
}

/// The one log viewer window; `show(search:)` reuses it (upstream `ShowForLink`).
@MainActor
final class LogViewerWindowController: DiagnosticsWindowController {
    let model: LogViewerModel

    init(model: LogViewerModel) {
        self.model = model
        super.init(title: "\(AppInfo.name) Log Viewer", content: LogViewerView(model: model),
                   size: NSSize(width: 900, height: 600), resizable: true, autosaveName: "GreenshotLogViewer")
        keyWindow?.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private static var shared: LogViewerWindowController?

    /// Opens the viewer on the app's log; with a search text only its entries are shown (the level isn't changed).
    static func show(search: String?) {
        let controller = shared ?? LogViewerWindowController(model: LogViewerModel(fileURL: LogCenter.fileURL ?? AppInfo.logFile,
                                                                                 followsLog: true))
        shared = controller
        if let search {
            controller.model.search = search
        }
        if !controller.isOpen {
            controller.model.load()
            controller.model.startFollowing()
        } else if search != nil {
            controller.model.applySearch()
        }
        controller.present()
    }

    override func didClose() {
        model.stopFollowing()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_F5 {
            model.load()
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            model.focusSearch()
            return true
        }
        return false
    }

    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("ExternalCommand")

/// Runs a configured external command with the screenshot as a file: port of upstream
/// `Greenshot.Plugin.ExternalCommand/Destinations/ExternalCommandDestination.cs`. The command runs off the main
/// thread; its output can put a URL (e.g. from an upload script) or all of it on the clipboard.
@MainActor
enum ExternalCommandRunner {
    /// Exit status of `/usr/bin/env` when the command isn't found.
    private static let notFoundStatus: Int32 = 127

    /// `savedFile` is the capture's own file when it has one (upstream `captureDetails.Filename`); otherwise the
    /// command gets a temporary file in its format. A command in the background counts as done once it started
    /// (upstream); one that isn't waits for its end.
    static func run(_ command: ExternalCommand, capture: Capture, settings: SettingsStore, saver: ImageSaver,
                    savedFile: URL? = nil, completion: @escaping ExportCompletion = { _ in }) {
        let file: URL
        // The capture's own file only in the command's format: a command set up for JPEG must not get a HEIC.
        if let savedFile, ImageFormat(fileExtension: savedFile.pathExtension) == command.format {
            file = savedFile
        } else {
            do {
                file = try TemporaryCaptureFile.write(capture, settings: settings, format: command.format)
            } catch {
                ErrorPresenter.show(error, title: "The screenshot could not be written for \(command.name)")
                completion(.failed(error.localizedDescription, target: command.name))
                return
            }
        }
        let fill = filler(for: capture, settings: settings)
        guard let (executable, arguments) = resolve(command, file: file.path, fill: fill) else {
            ErrorPresenter.show(message: "\(command.name): the program was not found",
                                detail: "“\(command.command)” is not an executable file. Check it in Settings › Destinations.")
            completion(.failed("The program was not found.", target: command.name))
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            ErrorPresenter.show(error, title: "\(command.name) could not be started")
            completion(.failed(error.localizedDescription, target: command.name))
            return
        }
        if command.runInBackground { completion(.succeeded(fileURL: file, target: command.name, clearsModified: false)) }
        DispatchQueue.global(qos: .userInitiated).async {
            // Both pipes are read before waiting, or a chatty command blocks on a full pipe.
            var outData = Data()
            let reading = DispatchGroup()
            reading.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                outData = output.fileHandleForReading.readDataToEndOfFile()
                reading.leave()
            }
            let errData = errors.fileHandleForReading.readDataToEndOfFile()
            reading.wait()
            process.waitUntilExit()
            let status = process.terminationStatus
            let out = String(decoding: outData, as: UTF8.self)
            let err = String(decoding: errData, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let result = finish(command, status: status, output: out, errors: err, file: file, saver: saver)
                    if !command.runInBackground { completion(result) }
                }
            }
        }
    }

    /// Fills the pattern variables (`${title}`, `${YYYY}`, `${HOME}`, …) of the command line (upstream
    /// `FilenameHelper.FillVariables`), without counting `${NUM}` up.
    static func filler(for capture: Capture, settings: SettingsStore) -> (String) -> String {
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        return { FilenamePattern.fill($0, context: context, filenameSafe: false) }
    }

    /// The program and its arguments: a path runs as it is, an app bundle (`….app`) opens the file with `open -a`,
    /// a bare name is looked up in the PATH by `/usr/bin/env`. Nil when a path isn't executable.
    static func resolve(_ command: ExternalCommand, file: String, fill: (String) -> String = { $0 }) -> (URL, [String])? {
        guard let program = ExternalCommandLine.program(command.command, fill: fill) else { return nil }
        let arguments = ExternalCommandLine.arguments(command.arguments, file: file, fill: fill)
        switch program {
        case .application(let path):
            return (URL(fileURLWithPath: "/usr/bin/open"), ["-a", path] + arguments)
        case .executable(let path):
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return (URL(fileURLWithPath: path), arguments)
        case .searchPath(let name):
            return (URL(fileURLWithPath: "/usr/bin/env"), [name] + arguments)
        }
    }

    /// Whether the command's program is there (upstream `ExternalCommandPlugin.IsCommandValid`). A program with
    /// pattern variables counts as there.
    static func isAvailable(_ command: ExternalCommand) -> Bool {
        guard !command.command.contains("${") else { return true }
        guard let program = ExternalCommandLine.program(command.command) else { return false }
        let manager = FileManager.default
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        return ExternalCommandLine.isAvailable(program, fileExists: manager.fileExists(atPath:),
                                               isExecutable: manager.isExecutableFile(atPath:), searchPath: path)
    }

    private static var icons: [String: NSImage] = [:]

    /// The icon of the command's program for menus (upstream `IconCache.IconForCommandAsync`): the app it opens
    /// (`….app`, or `open -a Name`), else the program file's icon. 16 points, cached.
    static func icon(for command: ExternalCommand) -> NSImage? {
        let cacheKey = command.command + "\u{1}" + command.arguments
        if let cached = icons[cacheKey] { return cached }
        var path: String?
        switch ExternalCommandLine.program(command.command) {
        case .some(.application(let app)): path = app
        case .some(.executable(let executable)): path = executable
        case .some(.searchPath), .none: path = nil
        }
        if let name = ExternalCommandLine.applicationName(inArguments: command.arguments), let app = applicationPath(named: name) {
            path = app
        }
        guard let path, FileManager.default.fileExists(atPath: path),
              let icon = NSWorkspace.shared.icon(forFile: path).copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        icons[cacheKey] = icon
        return icon
    }

    /// An application by name or bundle ID, as `open -a` finds it.
    private static func applicationPath(named name: String) -> String? {
        if name.contains("/") { return (name as NSString).expandingTildeInPath }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url.path }
        let file = name.hasSuffix(".app") ? name : name + ".app"
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                       ("~/Applications" as NSString).expandingTildeInPath]
        return folders.map { ($0 as NSString).appendingPathComponent(file) }.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// What a command wrote, in the log (upstream `ExternalCommandDestination.RunCommandAsync`): its errors always, as a
    /// warning; its output only when "Write the output to the log" is on (upstream `ShowStandardOutputInLog`). The log
    /// makes the text harmless (`LogSanitizer`) and limits its length; nothing else of the command is logged.
    nonisolated static func logOutput(of name: String, output: String, errors: String, showOutput: Bool) {
        let shownOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if showOutput, !shownOutput.isEmpty { log.info("\(name) wrote:\n\(shownOutput)") }
        let shownErrors = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shownErrors.isEmpty { log.warn("\(name) wrote errors:\n\(shownErrors)") }
    }

    private static func finish(_ command: ExternalCommand, status: Int32, output: String, errors: String, file: URL,
                               saver: ImageSaver) -> ExportResult {
        logOutput(of: command.name, output: output, errors: errors, showOutput: command.showOutputInLog)
        let trimmedErrors = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            let detail = trimmedErrors.isEmpty ? "It ended with exit code \(status)." : String(trimmedErrors.prefix(600))
            if command.runInBackground && status != notFoundStatus {
                saver.notify("\(command.name) failed", detail: detail, kind: .error)
            } else {
                ErrorPresenter.show(message: "\(command.name) failed", detail: detail)
            }
            return .failed(detail, target: command.name)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Like upstream: the output first, so a URL found in it replaces it on the clipboard.
        var copied: String?
        if command.copyOutputToClipboard, !trimmed.isEmpty {
            Clipboard.copy(text: trimmed)
            copied = "Copied its output"
        }
        if command.copyURLFromOutput, let url = ExternalCommandLine.firstURL(in: output) {
            Clipboard.copy(text: url)
            saver.notify("\(command.name): copied the URL", detail: url) {
                if let link = URL(string: url) { NSWorkspace.shared.open(link) }
            }
            return .succeeded(fileURL: file, link: URL(string: url), target: command.name, clearsModified: false)
        }
        if let copied {
            saver.notify("\(command.name) finished", detail: copied)
        }
        return .succeeded(fileURL: file, target: command.name, clearsModified: false)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Runs a configured external command with the screenshot as a temporary PNG: port of upstream
/// `Greenshot.Plugin.ExternalCommand/Destinations/ExternalCommandDestination.cs`. The command runs off the main
/// thread; its output can put a URL (e.g. from an upload script) or all of it on the clipboard.
@MainActor
enum ExternalCommandRunner {
    /// Exit status of `/usr/bin/env` when the command isn't found.
    private static let notFoundStatus: Int32 = 127

    static func run(_ command: ExternalCommand, capture: Capture, settings: SettingsStore, saver: ImageSaver) {
        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be written for \(command.name)")
            return
        }
        guard let (executable, arguments) = resolve(command, file: file.path) else {
            ErrorPresenter.show(message: "\(command.name): the program was not found",
                                detail: "“\(command.command)” is not an executable file. Check it in Settings › Destinations.")
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
            return
        }
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
                    finish(command, status: status, output: out, errors: err, saver: saver)
                }
            }
        }
    }

    /// The program and its arguments: a path runs as it is, an app bundle (`….app`) opens the file with `open -a`,
    /// a bare name is looked up in the PATH by `/usr/bin/env`. Nil when a path isn't executable.
    static func resolve(_ command: ExternalCommand, file: String) -> (URL, [String])? {
        let program = (command.command.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !program.isEmpty else { return nil }
        let arguments = ExternalCommandLine.arguments(command.arguments, file: file)
        if program.lowercased().hasSuffix(".app") || program.lowercased().hasSuffix(".app/") {
            return (URL(fileURLWithPath: "/usr/bin/open"), ["-a", program] + arguments)
        }
        if program.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: program) else { return nil }
            return (URL(fileURLWithPath: program), arguments)
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), [program] + arguments)
    }

    private static func finish(_ command: ExternalCommand, status: Int32, output: String, errors: String, saver: ImageSaver) {
        let trimmedErrors = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            let detail = trimmedErrors.isEmpty ? "It ended with exit code \(status)." : String(trimmedErrors.prefix(600))
            if command.runInBackground && status != notFoundStatus {
                saver.notify("\(command.name) failed", detail: detail, kind: .error)
            } else {
                ErrorPresenter.show(message: "\(command.name) failed", detail: detail)
            }
            return
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
            return
        }
        if let copied {
            saver.notify("\(command.name) finished", detail: copied)
        }
    }
}

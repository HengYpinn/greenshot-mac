// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the ExternalCommand step runs (upstream `Greenshot.Plugin.ExternalCommand/Recipes/ExternalCommandStep.cs`, and
/// docs/capture-recipes.md "External Command Step In Depth"): a command of the settings (`Command`) or a program of
/// its own (`CommandLine`), whose values win over the command's.
public struct RecipeExternalCommandPlan: Equatable, Sendable {
    /// The command's name, or the program's file name.
    public var name: String
    public var commandLine: String
    /// `{0}` is the file.
    public var arguments: String
    public var workingDirectory: String?
    public var format: ImageFormat
    public var jpegQuality: Int
    public var runInBackground: Bool
    public var outputToClipboard: Bool
    public var uriToClipboard: Bool
    public var reloadAfterExecution: Bool
    public var setOutputVariable: String?
    public var setExitCodeVariable: String?
    /// `Verb` is a Windows shell verb; upstream runs the process without the shell, where it has no effect.
    public var verb: String?

    /// Nil when there is no program to run (upstream logs it and the flow goes on).
    public init?(_ step: RecipeStepInvocation, commands: [ExternalCommand]) {
        func text(_ name: String) -> String? {
            guard let value = step.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let commandName = text("Command")
        let configured = commandName.flatMap { name in commands.first { recipeEquals($0.name, name) } }
        guard let commandLine = text("CommandLine") ?? configured?.command.trimmingCharacters(in: .whitespaces),
              !commandLine.isEmpty else { return nil }
        self.commandLine = commandLine
        name = commandName ?? URL(fileURLWithPath: commandLine).deletingPathExtension().lastPathComponent
        arguments = text("Arguments") ?? configured?.arguments ?? "{0}"
        workingDirectory = text("WorkingDirectory")
        format = text("Format").flatMap(ImageFormat.init(fileExtension:)) ?? configured?.format ?? .png
        jpegQuality = min(max(step.int("JpegQuality") ?? 90, 1), 100)
        runInBackground = (step.isSet("RunInBackground") ? step.bool("RunInBackground") : nil) ?? configured?.runInBackground ?? false
        outputToClipboard = (step.isSet("OutputToClipboard") ? step.bool("OutputToClipboard") : nil) ?? configured?.copyOutputToClipboard ?? false
        uriToClipboard = (step.isSet("UriToClipboard") ? step.bool("UriToClipboard") : nil) ?? configured?.copyURLFromOutput ?? false
        reloadAfterExecution = step.bool("ReloadAfterExecution") ?? false
        setOutputVariable = text("SetOutputVariable")
        setExitCodeVariable = text("SetExitCodeVariable")
        verb = text("Verb")
    }

    /// The file a former step wrote (the capture's own file, `Destination.Filename`) when it is there in the command's
    /// format; else the step writes a temporary file. Upstream takes any existing file; the Mac's commands get their format.
    public func reusableFile(_ candidates: [String?], exists: (String) -> Bool) -> URL? {
        for case let path? in candidates where !path.isEmpty && exists(path) {
            let url = URL(fileURLWithPath: path)
            if ImageFormat(fileExtension: url.pathExtension) == format { return url }
        }
        return nil
    }

    /// The variables after the command ended (upstream sets them unless it ran in the background).
    public func outputs(exitCode: Int32, output: String, error: String) -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "ExternalCommand.ExitCode": .number(Double(exitCode)),
            "ExternalCommand.Output": .string(output),
            "ExternalCommand.Error": .string(error)
        ]
        if let setOutputVariable { result[setOutputVariable] = .string(output) }
        if let setExitCodeVariable { result[setExitCodeVariable] = .number(Double(exitCode)) }
        if let uri = ExternalCommandLine.firstURL(in: output) { result["ExternalCommand.Uri"] = .string(uri) }
        return result
    }

    /// The export's result as upstream's destination reports it.
    public func result(exitCode: Int32, output: String, error: String, file: URL) -> ExportResult {
        guard exitCode == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(message.isEmpty ? "Exit code \(exitCode)" : String(message.prefix(600)), target: name)
        }
        let link = ExternalCommandLine.firstURL(in: output).flatMap(URL.init(string:))
        return .succeeded(fileURL: file, link: link, target: name, clearsModified: false)
    }
}

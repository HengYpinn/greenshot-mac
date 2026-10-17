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
    /// The program is the step's own `CommandLine` (already evaluated by the flow), not a configured command's.
    public var commandLineFromRecipe: Bool
    /// The arguments are the step's own `Arguments` (as written: their `${...}` are filled per argument).
    public var argumentsFromRecipe: Bool

    /// Nil when there is no program to run (upstream logs it and the flow goes on).
    public init?(_ step: RecipeStepInvocation, commands: [ExternalCommand]) {
        func text(_ name: String) -> String? {
            guard let value = step.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let commandName = text("Command")
        let configured = commandName.flatMap { name in commands.first { recipeEquals($0.name, name) } }
        let ownCommandLine = text("CommandLine")
        guard let commandLine = ownCommandLine ?? configured?.command.trimmingCharacters(in: .whitespaces),
              !commandLine.isEmpty else { return nil }
        self.commandLine = commandLine
        commandLineFromRecipe = ownCommandLine != nil
        name = commandName ?? URL(fileURLWithPath: commandLine).deletingPathExtension().lastPathComponent
        let ownArguments = text("Arguments")
        argumentsFromRecipe = ownArguments != nil
        arguments = ownArguments ?? configured?.arguments ?? "{0}"
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

    /// The file the flow saved (`Destination.Filename`) when it still shows the capture as it is now, is there and is in
    /// the command's format; else the step writes a temporary file of the capture as it is now. Never the file the
    /// capture was loaded from (the user's original, which the command or a reload could change). Upstream takes any
    /// existing file.
    public func reusableFile(_ savedByFlow: String?, unchangedSinceSaved: Bool, exists: (String) -> Bool) -> URL? {
        guard unchangedSinceSaved, let path = savedByFlow, !path.isEmpty, exists(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        return ImageFormat(fileExtension: url.pathExtension) == format ? url : nil
    }

    /// The arguments: the text split like a shell would first, so no value can add an argument or an option; then each
    /// argument filled: the step's own by the flow's expressions (`evaluate`; one whose values come out empty goes, as
    /// upstream's split after the evaluation drops it, one written empty ("") stays), a configured command's exactly as
    /// its destination does (`ExternalCommandLine.arguments` with the file name patterns, `fill`); `{0}` is the file.
    public func argumentList(file: String, evaluate: (String) -> String, fill: (String) -> String) -> [String] {
        guard argumentsFromRecipe else { return ExternalCommandLine.arguments(arguments, file: file, fill: fill) }
        return ExternalCommandLine.split(arguments).compactMap { argument in
            let evaluated = evaluate(argument)
            if evaluated.isEmpty, !argument.isEmpty { return nil }
            return evaluated.replacingOccurrences(of: "{0}", with: file)
        }
    }

    /// The program: the step's own command line as the flow evaluated it (no second filling), a configured command's
    /// with its file name patterns filled.
    public func program(fill: (String) -> String) -> ExternalCommandLine.Program? {
        ExternalCommandLine.program(commandLine, fill: commandLineFromRecipe ? { $0 } : fill)
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

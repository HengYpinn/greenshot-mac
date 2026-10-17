// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// Upstream `ExternalCommandStep` (Greenshot.Plugin.ExternalCommand/Recipes/ExternalCommandStep.cs): saves the capture
/// (or takes the file a step before wrote) and runs the command with it, waits for it unless it runs in the background,
/// and puts its exit code, output, errors and the first URL of the output into the flow; the output or the URL can go
/// to the clipboard; `ReloadAfterExecution` reads the file back into the capture (for in-place optimisers). Unlike the
/// destination it shows no dialogs: the flow's variables and the notification tell how it went.
struct RecipeExternalCommandExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("ExternalCommandStep: No surface available.")
            return
        }
        context.state = .exporting
        let commands = await MainActor.run { runtime.app.settings.value.externalCommands }
        guard let plan = RecipeExternalCommandPlan(step, commands: commands) else {
            context.log("ExternalCommandStep: No command line or executable configured for command '\(step.string("Command") ?? step.node.id)'.")
            return
        }
        // Upstream sets `Verb` with `UseShellExecute = false` (ExternalCommandStep.cs:333-343), where .NET doesn't use it
        // (only its ShellExecute start reads `Verb`): the verb has no effect there either.
        if let verb = plan.verb { context.log("ExternalCommandStep: the shell verb '\(verb)' has no effect (upstream runs the command without the shell too), ignored.") }
        // "Write the output to the log" of the configured command (upstream `ShowStandardOutputInLog`); errors always.
        let commandName = step.string("Command")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showOutput = !commandName.isEmpty && (commands.first { recipeEquals($0.name, commandName) }?.showOutputInLog ?? false)
        let designation = "External \(plan.name)"
        let file = try await Self.file(payload, plan: plan, context: context, runtime: runtime)
        // Before the arguments are filled: `${ExternalCommand.TargetFile}` in them is this file (upstream's example).
        context[variable: "ExternalCommand.TargetFile"] = .string(file.path)
        let prepared: Prepared
        do {
            prepared = try await Self.command(plan, file: file, payload: payload, context: context, runtime: runtime)
        } catch {
            await MainActor.run {
                RecipeStepExports.finish(.failed(error.localizedDescription, target: plan.name), designation: designation, context: context,
                                         runtime: runtime)
            }
            throw error
        }
        // The program only: the arguments may hold a page's address or an AI tool's values (S-N5).
        context.log("Executing external command: \(prepared.executable.lastPathComponent)")
        if plan.runInBackground {
            // The flow doesn't wait for it; the output variables aren't set (upstream).
            let name = plan.name
            Task.detached {
                guard let ran = try? await RecipeProcess.run(prepared.executable, arguments: prepared.arguments, in: prepared.workingDirectory)
                else { return }
                ExternalCommandRunner.logOutput(of: name, output: ran.output, errors: ran.error, showOutput: showOutput)
            }
            await MainActor.run {
                RecipeStepExports.finish(.succeeded(fileURL: prepared.file, target: plan.name, clearsModified: false), designation: designation,
                                         context: context, runtime: runtime)
            }
            context.log("External command '\(plan.name)' launched in background.")
            return
        }
        let ran: RecipeProcess.Outcome
        do {
            ran = try await RecipeProcess.run(prepared.executable, arguments: prepared.arguments, in: prepared.workingDirectory)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await MainActor.run {
                RecipeStepExports.finish(.failed(error.localizedDescription, target: plan.name), designation: designation, context: context,
                                         runtime: runtime)
            }
            throw RecipeStepError("\(plan.name) could not be started: \(error.localizedDescription)", errorType: "Win32Exception")
        }
        ExternalCommandRunner.logOutput(of: plan.name, output: ran.output, errors: ran.error, showOutput: showOutput)
        for (name, value) in plan.outputs(exitCode: ran.status, output: ran.output, error: ran.error) { context[variable: name] = value }
        let result = plan.result(exitCode: ran.status, output: ran.output, error: ran.error, file: prepared.file)
        await MainActor.run {
            // Like upstream: the output first, so a URL found in it replaces it on the clipboard.
            let output = ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if plan.outputToClipboard, !output.isEmpty { RecipePasteboard.write(text: output) }
            if plan.uriToClipboard, let uri = ExternalCommandLine.firstURL(in: ran.output) { RecipePasteboard.write(text: uri) }
            RecipeStepExports.finish(result, designation: designation, context: context, runtime: runtime)
        }
        if plan.reloadAfterExecution, let loaded = ImageLoader.load(prepared.file) {
            payload.image = loaded.image
            payload.scale = loaded.scale
            payload.annotations = []
            context.payload = payload
            context.log("Reloaded transformed image from '\(prepared.file.lastPathComponent)' (\(loaded.image.width)x\(loaded.image.height)).")
        }
        context.log("External command finished with exit code \(ran.status).")
    }

    struct Prepared: Sendable {
        var file: URL
        var executable: URL
        var arguments: [String]
        var workingDirectory: URL?
    }

    /// The file for the command: the one the flow saved when it still shows the capture as it is now, else a temporary
    /// file of the capture as it is now. Never the file the capture was loaded from (the user's original: the command
    /// would get the picture without the flow's changes, and a reload or an in-place tool would rewrite it).
    @MainActor
    private static func file(_ payload: RecipePayload, plan: RecipeExternalCommandPlan, context: RecipeFlowContext,
                             runtime: RecipeRuntime) throws -> URL {
        let state = runtime.flowState(context.executionId)
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let saved = context[variable: "Destination.Filename"]?.asString
        let current = saved.map { state.savedFileShows($0, payload: payload) } ?? false
        if let reused = plan.reusableFile(saved, unchangedSinceSaved: current, exists: { FileManager.default.fileExists(atPath: $0) }) {
            return reused
        }
        do {
            return try writeFile(capture, format: plan.format, quality: plan.jpegQuality, settings: runtime.app.settings)
        } catch {
            state.endExport()
            throw error
        }
    }

    /// The program and its arguments (`ExternalCommandRunner.resolve`'s ways: a path, an app bundle with `open -a`, a name
    /// in the PATH). The arguments are split before they are filled (`argumentList`); the step's own values are not
    /// filled twice (S-L1, S-N1).
    @MainActor
    private static func command(_ plan: RecipeExternalCommandPlan, file: URL, payload: RecipePayload, context: RecipeFlowContext,
                                runtime: RecipeRuntime) throws -> Prepared {
        let capture = payload.exportCapture()
        let fill = ExternalCommandRunner.filler(for: capture, settings: runtime.app.settings)
        let scope = context.scope()
        let arguments = plan.argumentList(file: file.path, evaluate: { context.evaluator.evaluate($0, in: scope).interpolationText },
                                          fill: fill)
        let executable: URL
        var argv: [String]
        switch plan.program(fill: fill) {
        case .application(let path)?:
            executable = URL(fileURLWithPath: "/usr/bin/open")
            argv = ["-a", path] + arguments
        case .executable(let path)? where FileManager.default.isExecutableFile(atPath: path):
            executable = URL(fileURLWithPath: path)
            argv = arguments
        case .searchPath(let name)?:
            executable = URL(fileURLWithPath: "/usr/bin/env")
            argv = [name] + arguments
        default:
            throw RecipeStepError("\(plan.name): the program “\(plan.commandLine)” was not found.", errorType: "FileNotFoundException")
        }
        // The step's own folder as the flow evaluated it; ~ expanded.
        let directory = plan.workingDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        var isFolder: ObjCBool = false
        let usable = directory.flatMap { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isFolder) && isFolder.boolValue ? $0 : nil }
        return Prepared(file: file, executable: executable, arguments: argv, workingDirectory: usable)
    }

    /// The capture as a file for the command, named by the filename pattern in a folder of its own
    /// (`TemporaryCaptureFile`), with the step's JPEG quality.
    @MainActor
    private static func writeFile(_ capture: Capture, format: ImageFormat, quality: Int, settings: SettingsStore) throws -> URL {
        let format = format.plainImage
        TemporaryCaptureFile.removeOldFiles()
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        var name = (FilenamePattern.fileName(settings.value.filenamePattern, context: context) as NSString).lastPathComponent
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "Screenshot" }
        let url = TemporaryCaptureFile.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        var options = ImageOutputOptions(settings: settings.value, format: format, scale: capture.scale, title: capture.title)
        options.jpegQuality = quality
        try ImageExporter.write(capture.image, to: url, options: options)
        return url
    }
}

/// A program run off the cooperative pool (its pipes are read and it is waited for on a global queue); cancelling the
/// task ends it.
enum RecipeProcess {
    struct Outcome: Sendable {
        var status: Int32
        var output: String
        var error: String
    }

    private final class Running: @unchecked Sendable {
        let lock = NSLock()
        var process: Process?
        var cancelled = false
    }

    static func run(_ executable: URL, arguments: [String], in directory: URL?) async throws -> Outcome {
        let running = Running()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Outcome, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    if let directory { process.currentDirectoryURL = directory }
                    let output = Pipe()
                    let errors = Pipe()
                    process.standardOutput = output
                    process.standardError = errors
                    process.standardInput = FileHandle.nullDevice
                    let cancelled: Bool = running.lock.withLock {
                        running.process = process
                        return running.cancelled
                    }
                    guard !cancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
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
                    let wasCancelled = running.lock.withLock { running.cancelled }
                    if wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: Outcome(status: process.terminationStatus, output: String(decoding: outData, as: UTF8.self),
                                                               error: String(decoding: errData, as: UTF8.self)))
                    }
                }
            }
        } onCancel: {
            let process: Process? = running.lock.withLock {
                running.cancelled = true
                return running.process
            }
            if let process, process.isRunning { process.terminate() }
        }
    }
}

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
        if let verb = plan.verb { context.log("ExternalCommandStep: the shell verb '\(verb)' has no meaning on the Mac, ignored.") }
        let designation = "External \(plan.name)"
        let prepared = try await Self.prepare(payload, plan: plan, context: context, runtime: runtime)
        context[variable: "ExternalCommand.TargetFile"] = .string(prepared.file.path)
        context.log("Executing external command: \(prepared.executable.path) \(prepared.arguments.joined(separator: " "))")
        if plan.runInBackground {
            // The flow doesn't wait for it; the output variables aren't set (upstream).
            Task.detached { _ = try? await RecipeProcess.run(prepared.executable, arguments: prepared.arguments, in: prepared.workingDirectory) }
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

    /// The file and the command line (`ExternalCommandRunner.resolve`: a path, an app bundle with `open -a`, a name in
    /// the PATH), with the pattern variables filled in.
    @MainActor
    private static func prepare(_ payload: RecipePayload, plan: RecipeExternalCommandPlan, context: RecipeFlowContext,
                                runtime: RecipeRuntime) throws -> Prepared {
        let settings = runtime.app.settings
        let capture = RecipeStepExports.begin(payload, context: context, runtime: runtime)
        let candidates = [payload.fileURL?.path, context[variable: "Destination.Filename"]?.asString]
        let file = try plan.reusableFile(candidates, exists: { FileManager.default.fileExists(atPath: $0) })
            ?? writeFile(capture, format: plan.format, quality: plan.jpegQuality, settings: settings)
        let fill = ExternalCommandRunner.filler(for: capture, settings: settings)
        let command = ExternalCommand(name: plan.name, command: plan.commandLine, arguments: plan.arguments, format: plan.format)
        guard let (executable, arguments) = ExternalCommandRunner.resolve(command, file: file.path, fill: fill) else {
            throw RecipeStepError("\(plan.name): the program “\(plan.commandLine)” was not found.", errorType: "FileNotFoundException")
        }
        let directory = plan.workingDirectory.map { URL(fileURLWithPath: (fill($0) as NSString).expandingTildeInPath, isDirectory: true) }
        var isFolder: ObjCBool = false
        let usable = directory.flatMap { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isFolder) && isFolder.boolValue ? $0 : nil }
        return Prepared(file: file, executable: executable, arguments: arguments, workingDirectory: usable)
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

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The executors that need no app (`RecipeStepRegistry.registerCoreExecutors`).
enum CoreStepExecutors {
    static func all(clipboard: (any RecipeClipboardWriting)?, cursorImages: (any RecipeCursorImageProviding)?) -> [(String, any RecipeStepExecutor)] {
        [
            (WellKnownStepType.setVariable, SetVariableExecutor()),
            (WellKnownStepType.conditional, NoOperationExecutor()),
            (WellKnownStepType.slot, NoOperationExecutor()),
            (WellKnownStepType.stdout, StdoutExecutor()),
            (WellKnownStepType.stderr, StderrExecutor())
        ] + imageExecutors(clipboard: clipboard, cursorImages: cursorImages)
    }
}

/// Conditional (the engine routes by its branches, upstream `ConditionalStep`) and Slot (extensions put their steps
/// there, upstream `SlotStep`): nothing to do when they run.
struct NoOperationExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {}
}

/// Upstream `SetVariableStep`: `Variable` + `Value`, and/or `Variables` (name to value). The values were evaluated once
/// by the engine and are stored as they are.
struct SetVariableExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        if let name = step.parameters.string("Variable")?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            context[variable: name] = step.parameters["Value"] ?? .null
            context.log("Set variable '\(name)'")
        }
        for member in step.parameters["Variables"]?.objectValue ?? [:] where !member.key.trimmingCharacters(in: .whitespaces).isEmpty {
            context[variable: member.key] = member.value
            context.log("Set variable '\(member.key)'")
        }
    }
}

/// Upstream `StdoutStep`: the text (default: the extracted text) to the caller's standard output.
struct StdoutExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        var text = step.parameters.string("Text") ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = context.payload?.extractedText ?? ""
        }
        context[variable: "LastStdout"] = .string(text)
        context[variable: "StdoutEmitted"] = .bool(true)
        context.log("[Stdout] \(text)")
        await context.output?.writeStdout(text)
    }
}

/// Upstream `StderrStep`: a message to the caller's standard error, the exit code, and (by default) the end of the flow.
struct StderrExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let text = step.parameters.string("Text") ?? ""
        let exitCode = step.int("ExitCode") ?? 1
        let abort = step.bool("Abort") ?? true
        context.exitCode = exitCode
        context[variable: "LastStderr"] = .string(text)
        context[variable: "StderrEmitted"] = .bool(true)
        context[variable: "ExitCode"] = .number(Double(exitCode))
        context.log("[Stderr] (ExitCode=\(exitCode)) \(text)")
        if !text.isEmpty {
            await context.output?.writeStderr(text)
        }
        if abort {
            context.abort(text.isEmpty ? "Aborted by Stderr step with exit code \(exitCode)" : text)
        }
    }
}

extension CoreStepExecutors {
    /// Filled by the image steps (Effect, Annotation, TextEffect, Processors, BarcodeScan).
    static func imageExecutors(clipboard: (any RecipeClipboardWriting)?, cursorImages: (any RecipeCursorImageProviding)?) -> [(String, any RecipeStepExecutor)] {
        [
            (WellKnownStepType.effect, EffectExecutor()),
            (WellKnownStepType.annotation, AnnotationExecutor(cursorImages: cursorImages)),
            (WellKnownStepType.textEffect, TextEffectExecutor()),
            (WellKnownStepType.processors, ProcessorsExecutor()),
            (WellKnownStepType.barcodeScan, BarcodeScanExecutor(clipboard: clipboard))
        ]
    }
}

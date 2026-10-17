// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Runs the nodes of one step type. RCORE registers the executors that need no app (SetVariable, Conditional, Slot,
/// Stdout, Stderr, Effect, Annotation, TextEffect, Processors, BarcodeScan); RAPP registers the others at launch.
///
/// Conventions the engine relies on: an executor reads its parameters from `step` (already evaluated once, unless the
/// contract says `evaluatesOwnParameters`) and never evaluates `${...}` in a value it got; a UserPrompt executor sets
/// the variable `UserChoice.<node id>` to the chosen key; an export records each export with `context.exports.add`;
/// Source sets `context.payload` (keeping a pre-supplied one); an executor that throws fails the node (error
/// transitions apply), one that is cancelled throws `CancellationError`. Executors run off the main thread and hop to
/// the main actor themselves for UI.
public protocol RecipeStepExecutor: Sendable {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws
}

/// A node about to run: its raw node, its parameters evaluated once, and its contract.
public struct RecipeStepInvocation: Sendable {
    public let node: RecipeNode
    /// The parameters with `${...}` evaluated (raw when `contract.evaluatesOwnParameters`).
    public let parameters: JSONObject
    public let contract: StepContract?

    public init(node: RecipeNode, parameters: JSONObject, contract: StepContract?) {
        self.node = node
        self.parameters = parameters
        self.contract = contract
    }

    /// The parameter, or the contract's default when it isn't set.
    public func value(_ name: String) -> JSONValue? { rcoreStub() }
    public func string(_ name: String) -> String? { value(name)?.asString }
    public func int(_ name: String) -> Int? { value(name)?.asInt }
    public func double(_ name: String) -> Double? { value(name)?.asDouble }
    public func bool(_ name: String) -> Bool? { value(name)?.asBool }
    public func strings(_ name: String) -> [String]? { value(name)?.asStrings }
    /// "#RRGGBB", "#AARRGGBB", "rgba(r,g,b,a)" with a = 0-255, or a .NET color name (upstream `ColorTranslator`).
    public func color(_ name: String) -> RGBAColor? { rcoreStub() }
    /// Set on the node (not the default).
    public func isSet(_ name: String) -> Bool { rcoreStub() }
    /// The three-tier precedence of docs/capture-recipes.md section 5: the run-time override in the flow variable
    /// `overrideVariable` (trigger, command line), then the node parameter; nil means "use the live setting".
    public func resolved(_ name: String, overrideVariable: String?, in context: RecipeFlowContext) -> JSONValue? { rcoreStub() }
}

/// An error with a type name that error transitions can match (`errorType`; upstream matches the .NET exception type,
/// e.g. "InvalidOperationException"). Other errors match by their Swift type name.
public struct RecipeStepError: Error, LocalizedError, Sendable {
    public var errorType: String
    public var message: String
    /// The type of the error that caused it; error transitions match it too (upstream matches `InnerException`).
    public var innerErrorType: String?

    public init(_ message: String, errorType: String = "RecipeStepError", innerErrorType: String? = nil) {
        self.message = message
        self.errorType = errorType
        self.innerErrorType = innerErrorType
    }

    public var errorDescription: String? { message }
}

/// The executors by step type (case-insensitive). The contracts come from the catalog; registering an executor for a
/// step type without a contract needs `register(contract:executor:)`.
public final class RecipeStepRegistry: @unchecked Sendable {
    public init(contracts: StepContractCatalog = .builtIn) { rcoreStub() }
    public var contracts: StepContractCatalog { rcoreStub() }
    public func register(_ stepType: String, executor: any RecipeStepExecutor) { rcoreStub() }
    public func register(contract: StepContract, executor: any RecipeStepExecutor) { rcoreStub() }
    public func executor(for stepType: String) -> (any RecipeStepExecutor)? { rcoreStub() }
    /// Registers RCORE's executors: SetVariable, Conditional, Slot, Stdout, Stderr, Effect, Annotation, TextEffect,
    /// Processors (OCR), BarcodeScan. `clipboard` is for BarcodeScan's `CopyToClipboard` (nil: not copied, logged);
    /// `cursorImages` draws the Annotation step's `CursorName` presets (nil: presets are skipped, logged).
    public func registerCoreExecutors(clipboard: (any RecipeClipboardWriting)? = nil,
                                      cursorImages: (any RecipeCursorImageProviding)? = nil) { rcoreStub() }
}

/// The pictures of the cursor presets of the Annotation step ("Arrow", "Hand", "IBeam", "Cross", "Wait", ...;
/// upstream's Windows cursor names): RAPP maps them to `NSCursor` images; Core itself doesn't use AppKit.
public protocol RecipeCursorImageProviding: Sendable {
    /// The picture and its hot spot (pixels from the top left), nil for an unknown preset.
    func cursorImage(named preset: String) async -> (image: CGImage, hotSpot: CGPoint)?
}

/// Copies text to the clipboard for Core's executors (RAPP: `NSPasteboard`); Core itself doesn't use AppKit.
public protocol RecipeClipboardWriting: Sendable {
    func copy(text: String) async
}

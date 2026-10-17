// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The contract of a trigger type: its parameters (for the recipe editor's forms), what it hands to the flow, and
/// whether it starts the recipe on its own or from outside (upstream `RecipeDescriber` risk, `RecipeContract.GetTriggerInputs`,
/// `TriggerRecipePreparer`).
public struct TriggerContract: Sendable {
    public var triggerType: String
    public var displayName: String
    public var description: String
    public var parameters: [ParameterContract]
    /// Variables the trigger sets (OpenFile: Filename, Editor: EditorForm, Extension: Capture and Browser; Commandline
    /// and AiTool: their declared arguments, see `RecipeContractAnalyzer.triggerInputs`).
    public var providedVariables: [VariableContract]
    /// The trigger hands the image to the flow (Extension).
    public var providesPayload: Bool
    /// Clipboard, Schedule, Commandline, OpenFile, Extension, AiTool: the approval asks for it separately and an edit
    /// that adds it needs a decision (upstream `RecipeEditApproval`).
    public var startsOnItsOwn: Bool
    /// The Source a recipe without one gets for this trigger (upstream `TriggerRecipePreparer`): Clipboard, CurrentEditor,
    /// File, Extension, else FullScreen.
    public var defaultSourceType: String

    public init(triggerType: String, displayName: String, description: String = "", parameters: [ParameterContract] = [],
                providedVariables: [VariableContract] = [], providesPayload: Bool = false, startsOnItsOwn: Bool = false,
                defaultSourceType: String = "FullScreen") {
        self.triggerType = triggerType
        self.displayName = displayName
        self.description = description
        self.parameters = parameters
        self.providedVariables = providedVariables
        self.providesPayload = providesPayload
        self.startsOnItsOwn = startsOnItsOwn
        self.defaultSourceType = defaultSourceType
    }
}

public struct TriggerContractCatalog: Sendable {
    public static var builtIn: TriggerContractCatalog { rcoreStub() }

    public init(_ contracts: [TriggerContract]) { rcoreStub() }
    public var all: [TriggerContract] { rcoreStub() }
    public func contract(for triggerType: String) -> TriggerContract? { rcoreStub() }
}

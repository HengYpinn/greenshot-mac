// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A kind of trigger the app provides (RAPP: hotkeys, the Recipes menu, the clipboard monitor, Open With, the editor
/// menu). The hub hands it the active triggers of its types whenever they change; it calls `RecipeTriggerHub.fire`.
@MainActor
public protocol RecipeTriggerSource: AnyObject {
    var triggerTypes: Set<String> { get }
    func sync(_ triggers: [ActiveRecipeTrigger])
    func stop()
}

/// Connects the trigger sources with the library and the runner (upstream `TriggerManager`).
@MainActor
public final class RecipeTriggerHub {
    public init(library: RecipeLibrary, runner: RecipeRunner) { rcoreStub() }
    public func register(_ source: any RecipeTriggerSource) { rcoreStub() }
    /// Recomputes the active triggers and syncs every source (after reload, approval, settings change).
    public func sync() { rcoreStub() }
    /// A trigger fired: starts its recipe with the trigger info (the runner prepares the recipe for the trigger). Nil
    /// when the trigger isn't active anymore.
    @discardableResult
    public func fire(_ trigger: ActiveRecipeTrigger, info: RecipeTriggerInfo, variables: [String: JSONValue] = [:],
                     objects: [String: any Sendable] = [:], payload: RecipePayload? = nil) -> RecipeFlowHandle? { rcoreStub() }
    public func stopAll() { rcoreStub() }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RSTEPS after the wave 4 prep.

import Foundation

/// An automatic step of the BeforeDestination slot (upstream `ExtensionChain`, Greenshot.Base/Recipes/RecipeExtension.cs):
/// its steps run on a copy of the capture for the destinations it is for; destinations with the same chains share one
/// copy (upstream `DestinationDispatcher.ExportWithChainsAsync`). RMANAGER's composer makes them (the app hands them
/// over through `RecipeRuntime.destinationChains`); RSTEPS's export steps run them.
public struct RecipeDestinationChain: Sendable, Equatable {
    public var extensionId: String
    public var extensionName: String?
    /// The automatic step's nodes between its In and Out, ids prefixed, ready to run on the copy, as the composer builds
    /// them: the running recipe's id and name (so `${recipe.*}` reads the recipe), `${option.<key>}` rewritten to
    /// `${option.<extension id>.<key>}` and the composition set, so the extension's option values resolve.
    public var flow: CaptureRecipe
    /// The destination designations it runs for (case-insensitive); empty: every destination.
    public var onlyDestinations: [String]

    public init(extensionId: String, extensionName: String? = nil, flow: CaptureRecipe, onlyDestinations: [String] = []) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.flow = flow
        self.onlyDestinations = onlyDestinations
    }

    public func runs(for designation: String) -> Bool {
        onlyDestinations.isEmpty
            || onlyDestinations.contains { $0.caseInsensitiveCompare(designation) == .orderedSame }
    }
}

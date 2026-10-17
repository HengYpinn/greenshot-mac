// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The `requires` ids the Mac satisfies (upstream `RecipeValidator.ExtensionAvailabilityCheck`): the upstream plug-ins
/// whose features are built in. Unknown ids fail with upstream's message naming the plug-in and its URL.
public struct RecipeRequirementCatalog: Sendable {
    public static var builtIn: RecipeRequirementCatalog { rcoreStub() }

    public init(available: Set<String>) { rcoreStub() }
    /// The error for the requirement, nil when it is satisfied.
    public func problem(with requirement: RecipeRequirement) -> String? { rcoreStub() }
}

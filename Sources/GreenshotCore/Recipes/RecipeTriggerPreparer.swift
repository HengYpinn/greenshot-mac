// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a trigger adds before the recipe runs (upstream `TriggerRecipePreparer`): a Source for its trigger when the
/// recipe has none, an editor destination when it has no destination (not for AI tools). Only `RecipeRunner` calls it
/// (once per flow, after the preflight); callers hand it the recipe as loaded.
public enum RecipeTriggerPreparer {
    public static func prepare(_ recipe: CaptureRecipe, triggerType: String) -> CaptureRecipe { rcoreStub() }
}

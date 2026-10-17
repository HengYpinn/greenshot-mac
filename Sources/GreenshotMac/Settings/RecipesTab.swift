// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import GreenshotCore
import SwiftUI

/// Settings › Recipes (RCP-002, APP-095): the recipe switch, the recipe files and their approvals (RUI), then the
/// option sections of the automatic steps and recipes (RMANAGER's `RecipeOptionsSections`). Filled in by the RUI package.
struct RecipesSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            RecipeOptionsSections(store: store)
        }
        .formStyle(.grouped)
    }
}

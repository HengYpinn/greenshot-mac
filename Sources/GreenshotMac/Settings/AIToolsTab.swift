// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by MCP after the wave 4 prep.

import GreenshotCore
import SwiftUI

/// Settings › AI Tools (AUT-085, APP-096). Filled in by the MCP package.
struct AIToolsSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View { Form {}.formStyle(.grouped) }
}

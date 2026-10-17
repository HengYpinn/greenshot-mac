// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

/// The OpenFile triggers (RCP-069, upstream `IpcSecurityDispatcher.HandleOpenFileAsync`). Filled in by the RUI package.
@MainActor
enum RecipeOpenFileTrigger {
    /// The files OPEN_FILE accepted (Finder's Open With, greenshot-cli, AppleScript, Services): runs the recipes of the
    /// active OpenFile triggers and returns the reply; nil when no recipe has an OpenFile trigger (the caller opens the
    /// files in the editor). A stock `recipe_file` (`RecipeRuntime.fire` answers `.direct`) opens the file in the editor.
    static func open(_ files: [URL], app: AppDelegate) async -> IPCReply? { nil }
}

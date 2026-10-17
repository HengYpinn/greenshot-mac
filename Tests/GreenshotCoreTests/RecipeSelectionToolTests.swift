// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

/// The InteractiveSelection step's `SelectionTool`: upstream's built-in tool ids, any case (CaptureWindow.xaml.cs:466-469).
@Suite struct RecipeSelectionToolTests {
    @Test func builtInIdsInAnyCase() {
        #expect(RecipeSelectionTool(id: "region") == .region)
        #expect(RecipeSelectionTool(id: "Window") == .window)
        #expect(RecipeSelectionTool(id: "TEXT") == .text)
        #expect(RecipeSelectionTool(id: "FixedSize") == .fixedSize)
        #expect(RecipeSelectionTool(id: "fixedsize") == .fixedSize)
        #expect(RecipeSelectionTool(id: " Region ") == .region)
    }

    /// A plug-in's tool can't be on the Mac, and nothing is no tool: the step starts in its SelectionMode.
    @Test func otherIdsAreNoTool() {
        #expect(RecipeSelectionTool(id: "MyPlugin.Tool") == nil)
        #expect(RecipeSelectionTool(id: "") == nil)
        #expect(RecipeSelectionTool(id: "   ") == nil)
        #expect(RecipeSelectionTool(id: "Fixed Size") == nil)
    }

    /// The ids are upstream's: the name of the capture mode, and "FixedSize".
    @Test func idsAreUpstreams() {
        let ids = RecipeSelectionTool.allCases.map(\.rawValue)
        #expect(ids == ["Region", "Window", "Text", "FixedSize"])
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The capture tool the InteractiveSelection step starts with: its parameter `SelectionTool`, the id of one of
/// upstream's capture tools (`Greenshot/Recipes/Steps/InteractiveSelectionStep.cs:53`).
///
/// Upstream's built-in tools are Region, Window and Text, whose id is the name of their capture mode
/// (`ICaptureTool.Id => Mode.ToString()`, Greenshot.Base/Interfaces/Capture/ICaptureTool.cs:102), and FixedSize
/// (`FixedSizeCaptureTool.cs:61`). The capture screen looks the id up case-insensitively and, when no tool has it, starts
/// with the tool of the step's `SelectionMode` (`CaptureWindow.xaml.cs:466-469`).
///
/// Upstream also adds the tools of plug-ins (`ICaptureToolProvider`, `CaptureWindow.xaml.cs` `CreateTools`). The Mac has
/// no plug-ins (CAP-095), so a plug-in's tool id can't exist here: such an id gives nil, and the step starts in its
/// `SelectionMode` like upstream does for an id it doesn't find.
public enum RecipeSelectionTool: String, CaseIterable, Equatable, Sendable {
    case region = "Region"
    case window = "Window"
    case text = "Text"
    case fixedSize = "FixedSize"

    /// The built-in tool with this id (any case, spaces around it ignored); nil for an empty or unknown id.
    public init?(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard let tool = Self.allCases.first(where: { recipeEquals($0.rawValue, trimmed) }) else { return nil }
        self = tool
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// An upstream destination designation in a recipe ("Editor", "FileNoDialog", "External MS Paint", "Jira") and the
/// Mac destination it means. Designations are case-insensitive; the Mac-only ones are named after `CaptureDestination`.
public struct RecipeDestinationDesignation: Sendable, Equatable {
    public var designation: String
    public var destination: CaptureDestination?
    /// For "External <name>": the external command of the settings.
    public var externalCommandName: String?

    public init(_ designation: String) { rcoreStub() }
    /// The designation upstream uses for a Mac destination ("FileNoDialog" for `.file`).
    public static func designation(for destination: CaptureDestination) -> String { rcoreStub() }
    /// Uploads (Jira, Confluence, Box, Dropbox) and external commands; nil for the others (upstream's destinations'
    /// `GetGatedActions`).
    public func gatedAction(_ environment: GateEnvironment) -> RecipeGatedAction? { rcoreStub() }
    /// For the describer: "Open in image editor (Editor)".
    public var displayName: String { rcoreStub() }
}

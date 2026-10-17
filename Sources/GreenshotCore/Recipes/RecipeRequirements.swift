// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The `requires` ids the Mac satisfies (upstream `RecipeValidator.ExtensionAvailabilityCheck`): the upstream plug-ins
/// whose features are built in. Unknown ids fail with upstream's message naming the plug-in and its URL.
public struct RecipeRequirementCatalog: Sendable {
    public static var builtIn: RecipeRequirementCatalog { builtInCatalog }
    private static let builtInCatalog = RecipeRequirementCatalog(available: [
        "Greenshot.Plugin.Zxing", "Greenshot.Plugin.ExternalCommand", "Greenshot.Plugin.Jira", "Greenshot.Plugin.Confluence",
        "Greenshot.Plugin.Box", "Greenshot.Plugin.Dropbox", "Greenshot.Plugin.Pdf", "Greenshot.Plugin.Office",
        "Greenshot.Plugin.RecipeEditor"
    ])

    private let available: Set<String>

    public init(available: Set<String>) {
        var ids = Set<String>()
        for id in available {
            ids.insert(id.lowercased())
            // Upstream also matches the plug-in by its name ("Zxing" for Greenshot.Plugin.Zxing).
            if id.lowercased().hasPrefix("greenshot.plugin.") { ids.insert(String(id.lowercased().dropFirst("greenshot.plugin.".count))) }
        }
        self.available = ids
    }

    /// The error for the requirement, nil when it is satisfied (upstream `RecipeValidator.ValidateRequirement`; the Mac's
    /// built-in features satisfy any minVersion).
    public func problem(with requirement: RecipeRequirement) -> String? {
        let id = requirement.id.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return "Recipe requirement is missing required 'id'." }
        guard !available.contains(id.lowercased()) else { return nil }
        let name = (requirement.name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let version = (requirement.minVersion?.isEmpty == false) ? " (v\(requirement.minVersion!)+)" : ""
        let url = (requirement.url?.isEmpty == false) ? " Download/install from: \(requirement.url!)" : ""
        return "This recipe requires the extension '\(name)'\(version) (ID: \(id)), which is not installed or is disabled.\(url)"
    }
}

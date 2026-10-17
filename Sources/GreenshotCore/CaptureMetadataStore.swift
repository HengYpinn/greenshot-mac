// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by BROWSER after the wave 4 prep.

import Foundation

/// Values a capture brings along for file name patterns (upstream `CaptureDetails.MetaData`), by the capture's date: the
/// Mac's `Capture` is a value, and its date is what every output path passes to `SettingsStore.patternContext`.
/// Filled in by the BROWSER package (wave 4).
public final class CaptureMetadataStore: @unchecked Sendable {
    public static let shared = CaptureMetadataStore()

    public init() {}

    /// Remembers `metadata` ("url", "browser", "source", …) for the capture taken at `date`.
    public func record(_ metadata: [String: String], forCaptureAt date: Date) {}

    /// The pattern variables of the capture taken at `date`: what was recorded for it, and the browser's active tab.
    public func patternMetadata(forCaptureAt date: Date) -> [String: String] { [:] }
}

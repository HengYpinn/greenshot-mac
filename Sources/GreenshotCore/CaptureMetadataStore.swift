// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Values a capture brings along for file name patterns (upstream `CaptureDetails.MetaData`), by the capture's date: the
/// Mac's `Capture` is a value, and its date is what every output path passes to `SettingsStore.patternContext` (the
/// editor keeps it in `EditorDocument.captureDate`). In memory, for the most recent captures: a restored editor or a
/// reopened `.greenshot` file has none, like upstream's in-memory details.
public final class CaptureMetadataStore: @unchecked Sendable {
    public static let shared = CaptureMetadataStore()

    /// How many captures are remembered.
    public static let capacity = 64

    private let lock = NSLock()
    private var entries: [(date: Date, metadata: [String: String])] = []
    private let browser: BrowserContext

    public init(browser: BrowserContext = .shared) {
        self.browser = browser
    }

    /// Remembers `metadata` ("url", "browser", "source", …) for the capture taken at `date`; a second record for the same
    /// capture adds to the first (later values win). Empty values are left out.
    public func record(_ metadata: [String: String], forCaptureAt date: Date) {
        let values = metadata.filter { !$0.value.isEmpty }
        guard !values.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if let index = entries.firstIndex(where: { $0.date == date }) {
            let merged = entries[index].metadata.merging(values) { _, new in new }
            entries.remove(at: index)
            entries.append((date, merged))
        } else {
            entries.append((date, values))
        }
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// What was recorded for the capture taken at `date`.
    public func metadata(forCaptureAt date: Date) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.last { $0.date == date }?.metadata ?? [:]
    }

    /// The pattern variables of the capture taken at `date`: what was recorded for it, and the browser's active tab
    /// (`Browser.*`, read now). The capture's own values win.
    public func patternMetadata(forCaptureAt date: Date) -> [String: String] {
        browser.patternVariables.merging(metadata(forCaptureAt: date)) { _, own in own }
    }
}

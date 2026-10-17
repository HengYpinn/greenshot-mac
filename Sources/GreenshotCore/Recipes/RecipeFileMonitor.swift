// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Watches the folders of recipe files for changes to `*.gsrecipe.json` (upstream `FileSystemWatcher`) and reports a
/// changed file once it has been quiet for `debounce` seconds (upstream 1.5 s).
public final class RecipeFileMonitor: @unchecked Sendable {
    public init(debounce: TimeInterval = 1.5, onChange: @escaping @Sendable (URL) -> Void) { rcoreStub() }
    public func watch(_ fileURL: URL) { rcoreStub() }
    public func stopAll() { rcoreStub() }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The excluded applications in recipes started by an AI tool (upstream `AiToolCapture`, `AiToolAccess.IsProcessExcluded`):
/// RSTEPS's Source step refuses their windows and blacks them out in pictures of the screen. Called on the step
/// executors' threads, so the list is a copy behind a lock, refreshed by `AIToolsCenter` when the settings change.
final class AIToolsCaptureGuard: RecipeAIToolCaptureGuard, @unchecked Sendable {
    private let lock = NSLock()
    private var excluded: [String]

    init(excluded: [String]) {
        self.excluded = excluded
    }

    var excludedApplications: [String] {
        get { lock.withLock { excluded } }
        set { lock.withLock { excluded = newValue } }
    }

    func refusal(for window: WindowInfo) -> String? {
        let app = NSRunningApplication(processIdentifier: window.pid)
        let names = [window.appName, app?.localizedName, app?.bundleIdentifier, app?.executableURL?.lastPathComponent]
        guard AIToolExclusion.isExcluded(names: names, excluded: excludedApplications) else { return nil }
        return "Windows of '\(window.appName)' are excluded from AI tools (Settings › AI Tools)."
    }

    func redacted(_ image: CGImage, scale: CGFloat, origin: CGPoint) -> (image: CGImage, count: Int) {
        let list = excludedApplications
        guard !list.isEmpty else { return (image, 0) }
        // Every visible window, also untitled popups and the quick access panels of password managers
        let frames = AIToolsWindows.windows(allLevels: true)
            .filter { AIToolExclusion.isExcluded(names: $0.names, excluded: list) }
            .map(\.frame)
        let rects = AIToolExclusion.redactionRects(windowFrames: frames, origin: origin, scale: scale,
                                                   pixelWidth: image.width, pixelHeight: image.height)
        guard !rects.isEmpty, let blacked = AIToolExclusion.blackOut(image, rects: rects) else { return (image, 0) }
        return (blacked, rects.count)
    }
}

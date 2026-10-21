// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The excluded applications in recipes started by an AI tool (upstream `AiToolCapture`, `AiToolAccess.IsProcessExcluded`):
/// RSTEPS's Source step refuses their windows and blacks them out in pictures of the screen, the RecordVideo step refuses
/// their windows and leaves them out of a display or region (`RecipeRecordVideoPlan.aiToolRule`). Called on the step
/// executors' threads, so the list is a copy behind a lock, refreshed by `AIToolsCenter` when the settings change.
final class AIToolsCaptureGuard: RecipeAIToolCaptureGuard, @unchecked Sendable {
    /// How long the frames noted when an AI tool's run started count for its pictures.
    static let noteLifetime: TimeInterval = 120

    private let lock = NSLock()
    private var excluded: [String]
    private var noted: [(time: Date, frames: [CGRect])] = []

    init(excluded: [String]) {
        self.excluded = excluded
    }

    var excludedApplications: [String] {
        get { lock.withLock { excluded } }
        set { lock.withLock { excluded = newValue } }
    }

    func refusal(for window: WindowInfo) -> String? {
        AIToolExclusion.refusal(appName: window.appName, names: window.applicationNames, excluded: excludedApplications)
    }

    /// RUN_AI_TOOL, before the flow starts: the excluded windows now. A window that moves or closes while the picture is
    /// taken is blacked out where it was before and where it is after (the picture is taken in between).
    func noteRunStarting() {
        let frames = excludedFrames(excludedApplications)
        let now = Date()
        lock.withLock {
            noted = noted.filter { now.timeIntervalSince($0.time) < Self.noteLifetime }
            noted.append((now, frames))
        }
    }

    func redacted(_ image: CGImage, scale: CGFloat, origin: CGPoint) -> (image: CGImage, count: Int) {
        let list = excludedApplications
        guard !list.isEmpty else { return (image, 0) }
        let now = Date()
        let before = lock.withLock { noted.filter { now.timeIntervalSince($0.time) < Self.noteLifetime }.flatMap(\.frames) }
        let frames = before + excludedFrames(list)
        let rects = AIToolExclusion.redactionRects(windowFrames: frames, origin: origin, scale: scale,
                                                   pixelWidth: image.width, pixelHeight: image.height)
        guard !rects.isEmpty else { return (image, 0) }
        if let blacked = AIToolExclusion.blackOut(image, rects: rects) { return (blacked, rects.count) }
        // Fail closed: nothing of the picture rather than an excluded window
        log.error("The windows of excluded applications could not be blacked out; the AI tool gets a black picture.")
        return (AIToolExclusion.blackImage(width: image.width, height: image.height) ?? image, rects.count)
    }

    /// The frames of every visible window of the excluded applications, also untitled popups and the quick access panels
    /// of password managers.
    private func excludedFrames(_ list: [String]) -> [CGRect] {
        guard !list.isEmpty else { return [] }
        return AIToolsWindows.windows(allLevels: true).filter { AIToolExclusion.isExcluded(names: $0.names, excluded: list) }.map(\.frame)
    }

    private let log = Log("AITools")
}

extension WindowInfo {
    /// The names an excluded application is matched by besides `appName`: the app's name, bundle identifier and
    /// executable.
    var applicationNames: [String?] {
        let app = NSRunningApplication(processIdentifier: pid)
        return [app?.localizedName, app?.bundleIdentifier, app?.executableURL?.lastPathComponent]
    }
}

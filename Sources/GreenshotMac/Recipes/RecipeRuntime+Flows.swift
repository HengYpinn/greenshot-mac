// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// What the app keeps for one running flow: the exports for the Notification step, the hold on the destinations' own
/// messages while the flow exports, and the app to give the focus back to after a screen capture (like
/// `CaptureCoordinator.returnFocus`).
@MainActor
final class RecipeFlowAppState {
    /// The exports of the flow in the order they ended (declined ones aren't there), and how many were announced.
    private(set) var exports: [ExportResult] = []
    private var announced = 0
    /// Holds back "Saved…/Copied…" while the flow exports: its Notification step shows them together (upstream).
    private var hold: NotificationExportLog?
    /// The app that was in front when the flow started; gets the focus back after a capture from the screen.
    var previousApp: pid_t?
    var capturedFromScreen = false

    /// An export of the flow starts: from now on until the flow ends, the destinations' information messages wait.
    func holdMessages(of capture: Capture, settings: SettingsStore) {
        if hold == nil { hold = NotificationExportLog(capture: capture, settings: settings) }
    }

    /// An export of the flow ended.
    func record(_ result: ExportResult) {
        guard result.status != .declined else { return }
        exports.append(result)
    }

    /// The exports since the last call (the Notification step).
    func takeUnannounced() -> [ExportResult] {
        let new = Array(exports[announced...])
        announced = exports.count
        return new
    }

    /// The flow ended: the destinations' messages show again.
    func finish() {
        hold?.release()
        hold = nil
    }
}

extension RecipeRuntime {
    func flowState(_ id: UUID) -> RecipeFlowAppState {
        if let state = flowStates[id] { return state }
        let state = RecipeFlowAppState()
        flowStates[id] = state
        return state
    }

    /// The runner's events, on the main actor.
    func flowEvent(_ event: RecipeFlowEvent) {
        guard case .flowFinished(let result) = event else { return }
        guard let state = flowStates.removeValue(forKey: result.flowId) else { return }
        state.finish()
        if state.capturedFromScreen { returnFocus(to: state.previousApp) }
        if result.state == .failed { log.info("Recipe '\(result.recipeId)' failed: \(result.reason ?? "")") }
    }

    /// Gives the focus back to the app that had it, unless a window of this app (an editor) is open now
    /// (`CaptureCoordinator.returnFocus`).
    private func returnFocus(to pid: pid_t?) {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is OverlayWindow) }
        if !ownWindowOpen { app.activate() }
    }
}

// MARK: Host objects (not readable by expressions)

/// "TargetWindow": the window to capture (upstream `CaptureWindow(IInteropWindow)`, the menu's window list).
final class RecipeWindowObject: @unchecked Sendable {
    let window: WindowInfo

    init(window: WindowInfo) {
        self.window = window
    }
}

/// "TargetDisplay" (Mac only): the display the menu bar's per-display item captures.
struct RecipeDisplayObject: Sendable {
    let displayID: CGDirectDisplayID
}

/// "Capture": the browser extension's capture as handed over (upstream passes its `ICapture`).
final class RecipeCaptureObject: @unchecked Sendable {
    let payload: RecipePayload

    init(payload: RecipePayload) {
        self.payload = payload
    }
}

/// The frozen displays and windows of a screen Source, for the InteractiveSelection after it (a payload attachment).
final class RecipeFrozenScreens: @unchecked Sendable {
    static let key = "RecipeFrozenScreens"

    let frozen: FrozenDisplays
    let windows: [WindowInfo]
    /// The pointer goes into the picture (CaptureMouseCursor).
    let withPointer: Bool
    /// The union of the displays, Quartz global points: the payload image's top left.
    let bounds: CGRect

    init(frozen: FrozenDisplays, windows: [WindowInfo], withPointer: Bool, bounds: CGRect) {
        self.frozen = frozen
        self.windows = windows
        self.withPointer = withPointer
        self.bounds = bounds
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Starts captures and hands the result to the destinations. The captures of upstream's capture user guide:
/// region, window, full screen, last region and a window from the list.
@MainActor
final class CaptureCoordinator {
    private let settings: SettingsStore
    private let output: OutputManager
    private var busy = false

    init(settings: SettingsStore, output: OutputManager) {
        self.settings = settings
        self.output = output
    }

    /// The capture screen in region mode.
    func captureRegion() {
        interactive(.region)
    }

    /// The window hotkey: the active window right away, or the capture screen in window mode when
    /// "interactive window capture" is on.
    func captureWindowFromHotkey() {
        settings.value.interactiveWindowCapture ? interactive(.window) : captureActiveWindow()
    }

    /// The menu's "Capture window" always opens the capture screen in window mode, like upstream.
    func captureWindowInteractively() {
        interactive(.window)
    }

    /// Every display, or the one with `displayID`.
    func captureFullScreen(displayID: CGDirectDisplayID? = nil) {
        let showsCursor = settings.value.captureMousePointer
        run {
            let windows = ScreenCapturer.onScreenWindows()
            let screens = try await ScreenCapturer.freezeScreens(showsCursor: showsCursor)
            let chosen = displayID.map { id in screens.filter { $0.displayID == id } } ?? screens
            guard let result = ScreenComposer.image(of: ScreenComposer.union(of: chosen), from: chosen) else {
                throw CaptureError.nothingToCapture
            }
            return Capture(image: result.image, scale: result.scale,
                           title: ScreenCapturer.frontWindow(in: windows)?.displayTitle ?? "Full screen")
        }
    }

    /// The same area as the last capture again, without the capture screen.
    func captureLastRegion() {
        guard let region = settings.value.lastCapturedRegion else {
            captureRegion()
            return
        }
        let showsCursor = settings.value.captureMousePointer
        run {
            let windows = ScreenCapturer.onScreenWindows()
            let screens = try await ScreenCapturer.freezeScreens(showsCursor: showsCursor)
            guard let result = ScreenComposer.image(of: region, from: screens) else { throw CaptureError.nothingToCapture }
            return Capture(image: result.image, scale: result.scale, title: ScreenCapturer.title(for: region, in: windows))
        }
    }

    func captureActiveWindow() {
        let settings = self.settings.value
        run {
            guard let window = ScreenCapturer.frontWindow(in: ScreenCapturer.onScreenWindows()) else {
                throw CaptureError.windowNotFound
            }
            return try await ScreenCapturer.capture(window: window, showsCursor: settings.captureMousePointer,
                                                    includeShadow: settings.includeWindowShadow)
        }
    }

    /// "Capture window from list".
    func capture(window: WindowInfo) {
        let settings = self.settings.value
        run {
            try await ScreenCapturer.capture(window: window, showsCursor: settings.captureMousePointer,
                                             includeShadow: settings.includeWindowShadow)
        }
    }

    private func interactive(_ mode: CaptureOverlayController.Mode) {
        let zoomer = settings.value.zoomerEnabled
        run { [settings] in
            let windows = ScreenCapturer.onScreenWindows()
            let screens = try await ScreenCapturer.freezeScreens(showsCursor: false)
            guard let selection = await CaptureOverlayController.select(screens: screens, windows: windows, mode: mode, zoomer: zoomer),
                  let result = ScreenComposer.image(of: selection.rect, from: screens) else { return nil }
            settings.update { $0.lastCapturedRegion = selection.rect }
            let title = selection.window?.displayTitle ?? ScreenCapturer.title(for: selection.rect, in: windows)
            return Capture(image: result.image, scale: result.scale, title: title)
        }
    }

    /// Waits the capture delay, runs `body` and sends its capture to the destinations. One capture at a time.
    private func run(_ body: @escaping @MainActor () async throws -> Capture?) {
        guard !busy else {
            NSSound.beep()
            return
        }
        guard Permissions.ensureScreenCapture() else { return }
        busy = true
        let previousApp = NSWorkspace.shared.frontmostApplication
        Toast.dismiss()
        let delay = max(settings.value.captureDelayMilliseconds, 0)
        Task { @MainActor in
            defer { self.busy = false }
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                guard let capture = try await body() else {
                    self.returnFocus(to: previousApp)
                    return
                }
                if self.settings.value.playCameraSound { CameraSound.play() }
                self.output.handle(capture)
                self.returnFocus(to: previousApp)
            } catch {
                ErrorPresenter.show(error)
                self.returnFocus(to: previousApp)
            }
        }
    }

    /// Gives the focus back to the app that had it, unless a window of this app (an editor) is open now.
    private func returnFocus(to app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is OverlayWindow) }
        if !ownWindowOpen { app.activate() }
    }
}

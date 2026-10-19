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
    /// `byAutomation`: greenshot-cli, a link, AppleScript or Shortcuts started it (the capture screen waits for a click,
    /// `OverlayInputArming`); passed along with the call, also into the recipe that replaces the built-in capture.
    func captureRegion(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.region, byAutomation: byAutomation) == true { return }
        interactive(.region, startedByUser: !byAutomation)
    }

    /// The window hotkey: the active window right away, or the capture screen in window mode when
    /// "interactive window capture" is on.
    func captureWindowFromHotkey(byAutomation: Bool) {
        settings.value.interactiveWindowCapture ? captureWindowInteractively(byAutomation: byAutomation)
            : captureActiveWindow(byAutomation: byAutomation)
    }

    /// The menu's "Capture window" always opens the capture screen in window mode, like upstream.
    func captureWindowInteractively(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.window, byAutomation: byAutomation) == true { return }
        interactive(.window, startedByUser: !byAutomation)
    }

    /// Every display, or the one with `displayID` (the menu bar's items).
    func captureFullScreen(displayID: CGDirectDisplayID? = nil, byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.fullScreen(display: displayID), byAutomation: byAutomation) == true { return }
        captureFullScreen { screens in displayID.map { id in screens.filter { $0.displayID == id } } ?? screens }
    }

    /// The full screen hotkey: the display with the mouse, every display, or display number `screenToCapture`,
    /// as "Capture full screen" is set (upstream `ScreenCaptureMode`).
    /// `byAutomation`: a recipe that replaces this capture may show the capture screen (`captureRegion`).
    func captureFullScreenFromHotkey(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.fullScreenFromHotkey, byAutomation: byAutomation) == true { return }
        let mode = settings.value.screenCaptureMode
        let number = settings.value.screenToCapture
        // Numbered like the menu bar's list: in the order of NSScreen.screens, the main display first.
        let order = NSScreen.screens.map(\.displayID)
        captureFullScreen { screens in
            let ordered = screens.sorted { (order.firstIndex(of: $0.displayID) ?? Int.max) < (order.firstIndex(of: $1.displayID) ?? Int.max) }
            let chosen = CaptureScreenChoice.screens(for: mode, screenNumber: number, mouse: ScreenSpace.mouseLocation,
                                                     frames: ordered.map(\.frame))
            return chosen.map { ordered[$0] }
        }
    }

    private func captureFullScreen(choosing choose: @escaping @MainActor ([FrozenScreen]) -> [FrozenScreen]) {
        let showsCursor = settings.value.captureMousePointer
        let toneMapHDR = settings.value.toneMapHDRCaptures
        run {
            let windows = ScreenCapturer.onScreenWindows()
            let frozen = try await ScreenCapturer.freeze(withPointer: showsCursor, toneMapHDR: toneMapHDR)
            let chosen = choose(frozen.screens(withPointer: showsCursor))
            let title = ScreenCapturer.frontWindow(in: windows)?.displayTitle ?? "Full screen"
            guard let capture = frozen.capture(of: ScreenComposer.union(of: chosen), withPointer: showsCursor, title: title,
                                               only: Set(chosen.map(\.displayID)))
            else { throw CaptureError.nothingToCapture }
            return capture
        }
    }

    /// "Capture text", upstream's built-in recipe "OCR text to clipboard": the capture screen in text mode, the text
    /// goes to the clipboard.
    func captureText(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.text, byAutomation: byAutomation) == true { return }
        interactive(.text, startedByUser: !byAutomation)
    }

    /// The same area as the last capture again, without the capture screen. Without a last area nothing is captured,
    /// like upstream (`LastRegionCaptureSource.cs` aborts); the Mac beeps.
    func captureLastRegion(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.lastRegion, byAutomation: byAutomation) == true { return }
        guard let region = settings.value.lastCapturedRegion, !region.isEmpty else {
            NSSound.beep()
            return
        }
        let showsCursor = settings.value.captureMousePointer
        let toneMapHDR = settings.value.toneMapHDRCaptures
        run {
            let windows = ScreenCapturer.onScreenWindows()
            let frozen = try await ScreenCapturer.freeze(withPointer: showsCursor, toneMapHDR: toneMapHDR)
            guard let capture = frozen.capture(of: region, withPointer: showsCursor,
                                               title: ScreenCapturer.title(for: region, in: windows))
            else { throw CaptureError.nothingToCapture }
            return capture
        }
    }

    func captureActiveWindow(byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.activeWindow, byAutomation: byAutomation) == true { return }
        let settings = self.settings.value
        run {
            guard let window = ScreenCapturer.frontWindow(in: ScreenCapturer.onScreenWindows()) else {
                throw CaptureError.windowNotFound
            }
            return try await ScreenCapturer.capture(window: window, showsCursor: settings.captureMousePointer,
                                                    includeShadow: settings.includeWindowShadow,
                                             toneMapHDR: settings.toneMapHDRCaptures)
        }
    }

    /// "Capture window from list".
    func capture(window: WindowInfo, byAutomation: Bool) {
        if RecipeRuntime.shared?.interceptBuiltIn(.windowFromList(window), byAutomation: byAutomation) == true { return }
        let settings = self.settings.value
        run {
            try await ScreenCapturer.capture(window: window, showsCursor: settings.captureMousePointer,
                                             includeShadow: settings.includeWindowShadow,
                                             toneMapHDR: settings.toneMapHDRCaptures)
        }
    }

    /// The capture screen. The displays are frozen with and without the mouse pointer, so M can switch;
    /// "Capture the mouse pointer" decides which one it starts with.
    private func interactive(_ mode: CaptureOverlayController.Mode, startedByUser: Bool) {
        run { [settings] in
            let windows = ScreenCapturer.onScreenWindows(includingPanels: true)
            let frozen = try await ScreenCapturer.freeze(withPointer: true, toneMapHDR: settings.value.toneMapHDRCaptures)
            guard let selection = await CaptureOverlayController.select(screens: frozen.plain, pointerScreens: frozen.pointer,
                                                                        windows: windows, mode: mode, settings: settings,
                                                                        startedByUser: startedByUser)
            else { return nil }
            if let action = selection.barcodeAction {
                Self.perform(action)
                return nil
            }
            let title = selection.window?.displayTitle ?? ScreenCapturer.title(for: selection.rect, in: windows)
            // Text captures don't change the last region or the recent sizes, and have no pointer of their own.
            if let text = selection.text {
                guard let result = ScreenComposer.image(of: selection.rect, from: frozen.screens(withPointer: selection.includesPointer))
                else { return nil }
                return Capture(image: result.image, scale: result.scale, title: title, text: text)
            }
            guard let capture = frozen.capture(of: selection.rect, withPointer: selection.includesPointer, title: title)
            else { return nil }
            let size = CaptureSize(width: capture.image.width, height: capture.image.height)
            settings.update { values in
                values.lastCapturedRegion = selection.rect
                if selection.mode == .region || selection.mode == .fixedSize {
                    values.recentCaptureSizes = FixedSizeCapture.remember(size, in: values.recentCaptureSizes)
                }
                if let fixed = selection.fixedSize { values.fixedCaptureSize = fixed }
            }
            return capture
        }
    }

    /// The QR code menu of the capture screen: copy what the code says, or open its URL.
    private static func perform(_ action: BarcodeAction) {
        switch action {
        case .copy(let payload): Clipboard.copy(text: payload)
        case .open(let url): NSWorkspace.shared.open(url)
        }
    }

    /// The text mode's result goes to the clipboard as text instead of to the destinations.
    private func deliverText(_ text: String) {
        Clipboard.copy(text: text)
        let values = settings.value
        guard values.showNotifications, values.notificationLevel == .all else { return }
        let lines = text.split(whereSeparator: \.isNewline)
        let first = lines.first.map(String.init) ?? text
        let shortened = first.count > 60 ? String(first.prefix(59)) + "…" : first
        Toast.show(lines.count > 1 ? String(localized: "Copied \(lines.count) lines of text") : String(localized: "Copied the text"), detail: shortened)
    }

    /// Waits the capture delay, runs `body` and sends its capture to the destinations. One capture at a time.
    /// The direct path is running (delay, capture screen, start of the export): the recipe runner's flows check it.
    var isBusy: Bool { busy }

    private func run(_ body: @escaping @MainActor () async throws -> Capture?) {
        // A recipe flow may have the capture screen open.
        guard !busy, !CaptureOverlayController.isShowing, !(RecipeRuntime.shared?.isSelectionReserved ?? false) else {
            NSSound.beep()
            return
        }
        guard Permissions.ensureScreenCapture() else { return }
        busy = true
        let previousApp = NSWorkspace.shared.frontmostApplication
        Toast.dismiss()
        let delay = AppSettings.clampedCaptureDelay(settings.value.captureDelayMilliseconds)
        Task { @MainActor in
            defer { self.busy = false }
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                guard let capture = try await body() else {
                    self.returnFocus(to: previousApp)
                    return
                }
                if self.settings.value.playCameraSound { CameraSound.play(file: self.settings.value.notificationSound) }
                if let text = capture.text {
                    self.deliverText(text)
                } else {
                    self.output.handle(capture)
                }
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

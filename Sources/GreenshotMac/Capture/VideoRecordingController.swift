// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Video")

enum RecordingControllerError: LocalizedError {
    case busy

    var errorDescription: String? { "A recording is already running." }
}

/// Screen recordings: Record Screen / Window / Region… of the menu bar menu, the "Start or stop recording" hotkey, the
/// countdown, the recording indicator and what happens with the file. Upstream records video only in its recipe step
/// "Record Video" (`Greenshot/Recipes/Steps/RecordVideoRecipeStep.cs`); `record(_:countdown:area:deliver:)` is the
/// entry for that step (wave 4), so its recordings get the indicator too. One recording at a time.
@MainActor
final class VideoRecordingController {
    private let settings: SettingsStore
    private let saver: ImageSaver
    /// The recording that runs or is being saved.
    private(set) var recorder: VideoRecorder?
    private var countdown: RecordingCountdown?
    private var indicator: RecordingStatusItem?
    /// The capture screen is open to pick what to record.
    private var picking = false
    /// Quitting waits for the file.
    private var quitting = false

    init(settings: SettingsStore, saver: ImageSaver) {
        self.settings = settings
        self.saver = saver
    }

    /// What the menus and the indicator show; nil without a recording.
    var indicatorState: RecordingIndicatorState? {
        if let countdown = indicator?.state, case .countdown = countdown { return countdown }
        guard let recorder else { return nil }
        switch recorder.state {
        case .recording: return .recording(recorder.duration)
        case .paused: return .paused(recorder.duration)
        case .finalizing: return .saving
        default: return nil
        }
    }

    // MARK: Hotkey and menu

    /// The "Start or stop recording" hotkey: stops a recording, cancels a countdown, or starts what Settings › Video's
    /// "The hotkey records" says.
    func hotkeyPressed() {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if let recorder {
            if recorder.state.isActive { stopRecording() } else { NSSound.beep() }
            return
        }
        switch settings.value.video.hotkeyTarget {
        case .region: recordRegion()
        case .window: recordWindow()
        case .screen: recordScreen()
        }
    }

    /// The menu bar menu's items, after the capture items.
    func addMenuItems(to menu: NSMenu) {
        menu.addItem(.separator())
        let hotkey = settings.value.hotkeys.recordVideo
        if let state = indicatorState {
            RecordingMenus.items(for: state, hotkey: hotkey, actions: actions).forEach(menu.addItem)
            return
        }
        let target = settings.value.video.hotkeyTarget
        menu.addItem(screenItem(hotkey: target == .screen ? hotkey : nil))
        menu.addItem(RecordingMenus.item("Record Window…", target == .window ? hotkey : nil) { [weak self] in self?.recordWindow() })
        menu.addItem(RecordingMenus.item("Record Region…", target == .region ? hotkey : nil) { [weak self] in self?.recordRegion() })
    }

    /// "Record Screen"; with several displays a submenu with each one (named like "Capture Full Screen"'s).
    private func screenItem(hotkey: KeyCombo?) -> NSMenuItem {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            return RecordingMenus.item("Record Screen", hotkey) { [weak self] in self?.recordScreen() }
        }
        let item = NSMenuItem(title: "Record Screen", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Record Screen")
        submenu.autoenablesItems = false
        let frames = screens.map { CGDisplayBounds($0.displayID) }
        for (screen, frame) in zip(screens, frames) {
            let id = screen.displayID
            let title = ScreenPosition.label(name: screen.localizedName, frame: frame, among: frames)
            submenu.addItem(ClosureMenuItem(title: title) { [weak self] in self?.recordScreen(displayID: id) })
        }
        item.submenu = submenu
        return item
    }

    private var actions: RecordingActions {
        RecordingActions(stop: { [weak self] in self?.stopRecording() },
                         pause: { [weak self] in self?.recorder?.pause() },
                         resume: { [weak self] in self?.recorder?.resume() },
                         discard: { [weak self] in self?.discardRecording() },
                         cancelCountdown: { [weak self] in self?.cancelCountdown() })
    }

    // MARK: Starting

    /// What to record, its name for the file and where the countdown shows.
    private struct Choice {
        var target: VideoCaptureTarget
        var title: String
        var area: CGRect
    }

    /// A whole display: `displayID`, else the one with the mouse pointer.
    func recordScreen(displayID: CGDirectDisplayID? = nil) {
        start {
            let screens = NSScreen.screens
            let mouse = NSEvent.mouseLocation
            let chosen = displayID.flatMap { id in screens.first { $0.displayID == id } }
                ?? screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            guard let screen = chosen else { return nil }
            let id = screen.displayID
            return Choice(target: .display(id), title: screen.localizedName, area: CGDisplayBounds(id))
        }
    }

    /// A window picked on the capture screen in window mode.
    func recordWindow() {
        start { [weak self] in try await self?.pick(.window) }
    }

    /// A region picked on the capture screen (Space switches to window mode).
    func recordRegion() {
        start { [weak self] in try await self?.pick(.region) }
    }

    private func start(_ choose: @escaping @MainActor () async throws -> Choice?) {
        guard recorder == nil, countdown == nil, !picking else {
            NSSound.beep()
            return
        }
        guard Permissions.ensureScreenCapture() else { return }
        picking = true
        Task { @MainActor in
            do {
                guard let choice = try await choose() else {
                    picking = false
                    return
                }
                let video = settings.value.video
                guard let audio = await audioSource(for: video.audioSource) else {
                    picking = false
                    return
                }
                let url = RecordingOutputPath.url(folder: video.outputFolder, pattern: video.filenamePattern,
                                                  context: settings.patternContext(title: choice.title, date: Date()))
                var options = video.captureOptions(target: choice.target, outputURL: url)
                options.audioSource = audio
                picking = false
                try await record(options, countdown: video.countdownSeconds, area: choice.area)
            } catch is CancellationError {
                picking = false
            } catch {
                picking = false
                ErrorPresenter.show(error, title: "The recording could not be started")
            }
        }
    }

    /// The capture screen in `mode`; nil when cancelled.
    private func pick(_ mode: CaptureOverlayController.Mode) async throws -> Choice? {
        let windows = ScreenCapturer.onScreenWindows(includingPanels: true)
        let frozen = try await ScreenCapturer.freeze(withPointer: true)
        guard let selection = await CaptureOverlayController.select(screens: frozen.plain, pointerScreens: frozen.pointer,
                                                                    windows: windows, mode: mode, settings: settings),
              selection.barcodeAction == nil else { return nil }
        if selection.mode == .window, let window = selection.window {
            return Choice(target: .window(window.id), title: window.displayTitle, area: window.frame)
        }
        guard selection.rect.width >= 8, selection.rect.height >= 8 else { return nil }
        return Choice(target: .region(selection.rect), title: ScreenCapturer.title(for: selection.rect, in: windows),
                      area: selection.rect)
    }

    /// The sound to record: with the microphone, macOS's permission first. Nil when the user cancels.
    private func audioSource(for wanted: AudioCaptureSource) async -> AudioCaptureSource? {
        guard wanted.includesMicrophone else { return wanted }
        if await MicrophoneCapture.authorize() { return wanted }
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) may not use the microphone"
        alert.informativeText = "Allow it in System Settings › Privacy & Security › Microphone, or record without it."
        alert.addButton(withTitle: "Record Without Microphone")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return wanted == .systemAudioAndMicrophone ? .systemAudio : AudioCaptureSource.none
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(MicrophoneCapture.settingsURL)
            return nil
        default:
            return nil
        }
    }

    /// Records with `options` after a countdown of `countdown` seconds over `area` (Quartz global points; nil: the main
    /// display). The menu bar indicator shows it; when it ends the file goes to Settings › Video's destinations unless
    /// `deliver` is false (a recipe passes it on itself). Throws `CancellationError` when the countdown was cancelled.
    @discardableResult
    func record(_ options: VideoCaptureOptions, countdown seconds: Int = 0, area: CGRect? = nil,
                deliver: Bool = true) async throws -> VideoRecorder {
        guard recorder == nil, countdown == nil else { throw RecordingControllerError.busy }
        let indicator = showIndicator(seconds > 0 ? .countdown(seconds) : .recording(0))
        if seconds > 0 {
            let countdown = RecordingCountdown()
            self.countdown = countdown
            let place = area ?? CGDisplayBounds(CGMainDisplayID())
            let ranOut = await countdown.run(seconds: seconds, over: place) { indicator.state = .countdown($0) }
            self.countdown = nil
            guard ranOut else {
                hideIndicator()
                throw CancellationError()
            }
        }
        do {
            let recorder = try await VideoRecorder.start(options)
            self.recorder = recorder
            indicator.state = .recording(0)
            follow(recorder, deliver: deliver)
            return recorder
        } catch {
            hideIndicator()
            throw error
        }
    }

    private func follow(_ recorder: VideoRecorder, deliver: Bool) {
        recorder.onStateChange = { [weak self, weak recorder] _, new in
            guard let self, let recorder else { return }
            switch new {
            case .recording: self.indicator?.state = .recording(recorder.duration)
            case .paused: self.indicator?.state = .paused(recorder.duration)
            case .finalizing: self.indicator?.state = .saving
            default: break
            }
        }
        recorder.onDuration = { [weak self] elapsed in self?.indicator?.state = .recording(elapsed) }
        recorder.onError = { [weak self] error, fatal in
            if fatal {
                ErrorPresenter.show(error, title: "The recording failed")
            } else {
                self?.saver.notify("A problem while recording", detail: error.localizedDescription, kind: .warning)
            }
        }
        Task { @MainActor [weak self] in
            let result = await recorder.waitUntilFinished()
            self?.ended(recorder, result: result, deliver: deliver)
        }
    }

    private func ended(_ finished: VideoRecorder, result: VideoRecordingResult?, deliver: Bool) {
        guard recorder === finished else { return }
        recorder = nil
        hideIndicator()
        if quitting {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        guard let result, deliver else { return }
        VideoOutput.deliver(result, settings: settings, saver: saver)
    }

    // MARK: Stopping

    func stopRecording() {
        guard let recorder, recorder.state.isActive else { return }
        Task { try? await recorder.stop() }
    }

    func discardRecording() {
        guard let recorder, recorder.state.isActive else { return }
        Task {
            await recorder.cancel()
            saver.notify("The recording was discarded")
        }
    }

    func cancelCountdown() {
        countdown?.cancel()
    }

    /// Quitting: a running recording is saved first (`.terminateLater`, answered once the file is finished).
    func terminateReply() -> NSApplication.TerminateReply {
        if countdown != nil {
            cancelCountdown()
            return .terminateNow
        }
        guard let recorder, recorder.state.isActive || recorder.state == .finalizing else { return .terminateNow }
        log.info("Quitting: saving the recording first")
        quitting = true
        if recorder.state.isActive { Task { try? await recorder.stop() } }
        return .terminateLater
    }

    // MARK: Indicator

    private func showIndicator(_ state: RecordingIndicatorState) -> RecordingStatusItem {
        if let indicator {
            indicator.state = state
            return indicator
        }
        let item = RecordingStatusItem(state: state, hotkey: { [weak self] in self?.settings.value.hotkeys.recordVideo },
                                       actions: actions)
        indicator = item
        return item
    }

    private func hideIndicator() {
        indicator?.remove()
        indicator = nil
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import GreenshotCore
import ScreenCaptureKit

private let log = Log("Video")

enum VideoRecorderError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case regionOffScreen
    case notRecording

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The display is no longer connected."
        case .windowNotFound: return "The window is no longer on the screen."
        case .regionOffScreen: return "The area is not on a display."
        case .notRecording: return "Nothing is being recorded."
        }
    }
}

/// Sound besides the screen, like upstream's `IAudioCaptureProvider`: the microphone. `start` gets a handler for its
/// sample buffers and the time each was taken on the host clock.
protocol RecordingAudioProvider: AnyObject {
    func start(_ handler: @escaping @Sendable (CMSampleBuffer, CMTime) -> Void) throws
    func stop()
}

/// One screen recording: upstream `IVideoCaptureService.StartRecordingAsync` and `IVideoRecordingSession`
/// (`Greenshot.Base/Video/WindowsGraphicsCaptureVideoSession.cs`), with ScreenCaptureKit's stream in place of Windows
/// Graphics Capture and AVAssetWriter (`VideoFileWriter`) in place of the Media Foundation transcoder. Wave 4's recipe
/// step RecordVideo starts one through `VideoRecordingController.record`.
///
/// While it records it keeps the Mac awake (`preventSleep`), pauses while the screen is locked (`autoPauseOnLock`),
/// finishes the file before the Mac sleeps, and for a window stops when the window closes (`stopWhenWindowCloses`) like
/// upstream's recipe step.
@MainActor
final class VideoRecorder {
    let options: VideoCaptureOptions
    var outputURL: URL { options.outputURL }
    /// The video's size in pixels.
    let width: Int
    let height: Int
    private(set) var state: RecordingState = .unstarted

    /// Old and new state (upstream `StateChanged`).
    var onStateChange: ((RecordingState, RecordingState) -> Void)?
    /// Once a second while recording (upstream `DurationChanged`).
    var onDuration: ((TimeInterval) -> Void)?
    /// An error, and whether it ended the recording (upstream `ErrorOccurred`).
    var onError: ((Error, Bool) -> Void)?

    private let stream: SCStream
    private let output: VideoStreamOutput
    private let writer: VideoFileWriter
    private let microphone: RecordingAudioProvider?
    private let windowID: CGWindowID?
    private var timers: [Timer] = []
    private var activity: NSObjectProtocol?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var pausedByLock = false
    /// The Mac went to sleep: the recording was stopped for it (no menus should pop up afterwards).
    private(set) var stoppedForSleep = false
    private var finishing: Task<VideoRecordingResult, Error>?
    private var result: VideoRecordingResult?
    private var waiters: [CheckedContinuation<VideoRecordingResult?, Never>] = []

    /// Starts recording (upstream `StartRecordingAsync`). `microphone` replaces the default microphone, like
    /// upstream's `CustomAudioProvider`.
    static func start(_ options: VideoCaptureOptions, microphone: RecordingAudioProvider? = nil) async throws -> VideoRecorder {
        let setup = try await StreamSetup.make(for: options)
        let mic = options.audioSource.includesMicrophone ? (microphone ?? MicrophoneCapture()) : nil
        let recorder = try VideoRecorder(options: options, setup: setup, microphone: mic)
        try await recorder.begin()
        return recorder
    }

    private init(options: VideoCaptureOptions, setup: StreamSetup, microphone: RecordingAudioProvider?) throws {
        self.options = options
        width = setup.width
        height = setup.height
        windowID = setup.windowID
        self.microphone = microphone
        let bitrate = VideoDimensions.bitrate(options, width: setup.width, height: setup.height)
        writer = try VideoFileWriter(.init(url: options.outputURL, format: options.format, width: setup.width,
                                           height: setup.height, frameRate: options.frameRate, bitrate: bitrate,
                                           colorMode: options.colorMode, resizeBehavior: options.windowResizeBehavior,
                                           hasAudio: options.audioSource != .none, realTime: true))
        output = VideoStreamOutput(writer: writer, usesContentRect: setup.windowID != nil,
                                   systemAudio: options.audioSource.includesSystemAudio,
                                   microphone: options.audioSource.includesMicrophone)
        stream = SCStream(filter: setup.filter, configuration: setup.configuration, delegate: output)
        log.info("Recording \(options.target) to \(options.outputURL.lastPathComponent): \(setup.width)x\(setup.height), "
                 + "\(options.frameRate) fps, \(bitrate) bit/s, \(options.format.rawValue), sound \(options.audioSource.rawValue)")
    }

    private func begin() async throws {
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            if options.audioSource.includesSystemAudio {
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
            }
            output.onStop = { [weak self] error in
                Task { @MainActor in self?.streamStopped(error) }
            }
            try await stream.startCapture()
        } catch {
            writer.cancel()
            move(to: .failed)
            throw error
        }
        if let microphone {
            do {
                let output = self.output
                try microphone.start { buffer, time in output.receiveMicrophone(buffer, at: time) }
            } catch {
                log.warn("The microphone could not be recorded", error: error)
                onError?(error, false)
            }
        }
        move(to: .recording)
        keepAwake()
        observeSystem()
        startTimers()
    }

    // MARK: Control

    /// The recorded time, without pauses (upstream `Duration`).
    var duration: TimeInterval { writer.duration(at: Self.now) }

    /// Upstream `PauseAsync`: nothing is recorded and the time stands still.
    func pause() {
        guard state == .recording else { return }
        writer.pause(at: Self.now)
        move(to: .paused)
    }

    /// Upstream `ResumeAsync`.
    func resume() {
        guard state == .paused else { return }
        pausedByLock = false
        writer.resume(at: Self.now)
        move(to: .recording)
    }

    /// Stops and finishes the file (upstream `StopAsync`); a second call gets the same result.
    @discardableResult
    func stop() async throws -> VideoRecordingResult {
        if let result { return result }
        if let finishing { return try await finishing.value }
        guard state.isActive else { throw VideoRecorderError.notRecording }
        let task = Task { @MainActor in try await self.finish() }
        finishing = task
        return try await task.value
    }

    /// Stops and deletes the file (upstream `CancelAsync`).
    func cancel() async {
        guard state.isActive || state == .unstarted else { return }
        move(to: .cancelled)
        tearDown()
        try? await stream.stopCapture()
        writer.cancel()
        log.info("Recording cancelled")
        resolveWaiters(nil)
    }

    /// The result once the recording ended, by `stop` or by itself (the window closed, the time is up, the Mac goes to
    /// sleep); nil when it was cancelled or failed.
    func waitUntilFinished() async -> VideoRecordingResult? {
        if let result { return result }
        if state == .cancelled || state == .failed { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func finish() async throws -> VideoRecordingResult {
        let end = Self.now
        // Nothing after the stop goes into the file.
        writer.pause(at: end)
        move(to: .finalizing)
        tearDown()
        try? await stream.stopCapture()
        await output.drain()
        do {
            let finished = try await writer.finish(at: end)
            result = finished
            log.info("Recording finished: \(finished)")
            move(to: .stopped)
            resolveWaiters(finished)
            return finished
        } catch {
            log.error("The recording could not be finished", error: error)
            move(to: .failed)
            onError?(error, true)
            resolveWaiters(nil)
            throw error
        }
    }

    /// The stream ended by itself: the user stopped it in macOS's menu bar, the window is gone, or an error.
    private func streamStopped(_ error: Error) {
        guard state.isActive else { return }
        let nsError = error as NSError
        let userStopped = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userStopped.rawValue
        if userStopped {
            log.info("The recording was stopped in the menu bar")
        } else {
            log.warn("The screen recording stopped", error: error)
        }
        if writer.hasFrames {
            if !userStopped && !(windowID != nil && windowIsGone) { onError?(error, false) }
            Task { try? await self.stop() }
        } else {
            move(to: .failed)
            tearDown()
            writer.cancel()
            onError?(error, true)
            resolveWaiters(nil)
        }
    }

    private func move(to next: RecordingState) {
        guard state != next, state.canMove(to: next) else { return }
        let old = state
        state = next
        onStateChange?(old, next)
    }

    private func resolveWaiters(_ result: VideoRecordingResult?) {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume(returning: result) }
    }

    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    // MARK: The Mac around the recording

    /// No App Nap while recording, and with `preventSleep` no idle sleep either (upstream `PowerHelper`: the system
    /// stays awake, the display may sleep).
    private func keepAwake() {
        let activityOptions: ProcessInfo.ActivityOptions = options.preventSleep ? .userInitiated : .userInitiatedAllowingIdleSystemSleep
        activity = ProcessInfo.processInfo.beginActivity(options: activityOptions, reason: "Recording the screen")
    }

    /// Lock and unlock (upstream `SessionSwitch`), another user (fast user switching) and sleep (upstream
    /// `PowerModes.Suspend`).
    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { recorder in
            log.info("The Mac goes to sleep: finishing the recording")
            recorder.stoppedForSleep = true
            Task { try? await recorder.stop() }
        }
        guard options.autoPauseOnLock else { return }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.pauseForLock() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.pauseForLock() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resumeAfterLock() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.resumeAfterLock() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (VideoRecorder) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func pauseForLock() {
        guard state == .recording else { return }
        log.info("The screen is locked: pausing the recording")
        pause()
        pausedByLock = true
    }

    /// Only a pause of the lock ends with the unlock; one the user chose stays.
    private func resumeAfterLock() {
        guard state == .paused, pausedByLock else { return }
        log.info("The screen is unlocked: going on with the recording")
        resume()
    }

    private func startTimers() {
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timers.append(tick)
        guard windowID != nil, options.stopWhenWindowCloses else { return }
        // Upstream's recipe step looks every 250 ms whether the window still exists.
        let watch = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchWindow() }
        }
        RunLoop.main.add(watch, forMode: .common)
        timers.append(watch)
    }

    private func tick() {
        guard state == .recording else { return }
        let elapsed = duration
        onDuration?(elapsed)
        if options.maximumDuration > 0, elapsed >= options.maximumDuration {
            log.info("The recording reached its length of \(Int(options.maximumDuration)) s")
            Task { try? await stop() }
        }
    }

    private var windowIsGone: Bool {
        guard let windowID else { return false }
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] ?? []
        return !list.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }

    private func watchWindow() {
        guard state.isActive, windowIsGone else { return }
        log.info("The recorded window closed: finishing the recording")
        Task { try? await stop() }
    }

    private func tearDown() {
        timers.forEach { $0.invalidate() }
        timers = []
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        microphone?.stop()
    }
}

/// The stream's filter and settings for a target.
private struct StreamSetup {
    var filter: SCContentFilter
    var configuration: SCStreamConfiguration
    var width: Int
    var height: Int
    var windowID: CGWindowID?

    @MainActor
    static func make(for options: VideoCaptureOptions) async throws -> StreamSetup {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter
        let points: CGSize
        var windowID: CGWindowID?
        switch options.target {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw VideoRecorderError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            points = CGDisplayBounds(id).size
        case .region(let rect):
            let frames = content.displays.map { CGDisplayBounds($0.displayID) }
            guard let part = RecordingGeometry.displayRegion(for: rect, displays: frames) else {
                throw VideoRecorderError.regionOffScreen
            }
            if part.globalRect.size != rect.standardized.integral.size {
                log.info("The region is on several displays: recording the part on one of them")
            }
            filter = SCContentFilter(display: content.displays[part.displayIndex], excludingWindows: [])
            configuration.sourceRect = part.sourceRect
            points = part.sourceRect.size
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw VideoRecorderError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            points = window.frame.size
            configuration.ignoreShadowsSingleWindow = true
            windowID = id
        }
        let scale = CGFloat(filter.pointPixelScale)
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        let size = VideoDimensions.size(source: pixels, maximumSize: options.maximumSize, scaleFactor: options.scaleFactor,
                                        format: options.format)
        configuration.width = size.width
        configuration.height = size.height
        // A window: scaled down when it is larger than the video; scaled up too only for scale-to-fit (letterbox keeps
        // a smaller window at its size, `VideoFrameProcessor` centres it).
        configuration.scalesToFit = windowID == nil || options.windowResizeBehavior == .scaleToFit
        configuration.preservesAspectRatio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(options.frameRate, 1)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = options.captureCursor
        configuration.queueDepth = 6
        if options.audioSource.includesSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = Int(VideoEncoderSettings.audioSampleRate)
            configuration.channelCount = VideoEncoderSettings.audioChannels
            configuration.excludesCurrentProcessAudio = true
        }
        return StreamSetup(filter: filter, configuration: configuration, width: size.width, height: size.height,
                           windowID: windowID)
    }
}

/// Takes the stream's frames and sound into the writer, on its own queue.
final class VideoStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Greenshot screen recording")
    var onStop: (@Sendable (Error) -> Void)?
    private let writer: VideoFileWriter
    /// A window recording: the frame's content rectangle says where the window is in it.
    private let usesContentRect: Bool
    private let systemAudio: Bool
    private let microphone: Bool
    private var mixer = RecordingAudioMixer()
    private let converters = [RecordingAudioConverter(), RecordingAudioConverter()]
    private var loggedFrame = false

    init(writer: VideoFileWriter, usesContentRect: Bool, systemAudio: Bool, microphone: Bool) {
        self.writer = writer
        self.usesContentRect = usesContentRect
        self.systemAudio = systemAudio
        self.microphone = microphone
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen: video(sampleBuffer)
        case .audio: audio(sampleBuffer, source: 0, time: nil)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    /// A microphone buffer, from the microphone's own queue.
    func receiveMicrophone(_ buffer: CMSampleBuffer, at time: CMTime) {
        queue.async { [self] in audio(buffer, source: 1, time: time) }
    }

    /// Waits for what is queued and sends the rest of the mixed sound.
    func drain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if systemAudio && microphone, let rest = mixer.mix(flush: true) { write(rest) }
                continuation.resume()
            }
        }
    }

    private func video(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let content = usesContentRect ? contentRect(info, pixels: pixels) : nil
        writer.appendVideo(pixels, contentRect: content, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    /// The window's place in the frame in pixels: the content rectangle is in points of the surface. Should it be past
    /// the frame when scaled, it is taken as pixels.
    private func contentRect(_ info: [SCStreamFrameInfo: Any], pixels: CVPixelBuffer) -> CGRect? {
        guard let value = info[.contentRect], let rect = CGRect(dictionaryRepresentation: value as! CFDictionary) else {
            return nil
        }
        let scale = (info[.scaleFactor] as? CGFloat) ?? 1
        let width = CGFloat(CVPixelBufferGetWidth(pixels))
        let height = CGFloat(CVPixelBufferGetHeight(pixels))
        if !loggedFrame {
            loggedFrame = true
            let contentScale = (info[.contentScale] as? CGFloat) ?? 1
            log.debug("First window frame: \(Int(width))x\(Int(height)) pixels, content \(rect), scale \(scale), content scale \(contentScale)")
        }
        let scaled = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return scaled.maxX <= width + 4 && scaled.maxY <= height + 4 ? scaled : rect
    }

    private func audio(_ buffer: CMSampleBuffer, source: Int, time: CMTime?) {
        guard let converted = converters[source].convert(buffer, time: time?.seconds) else { return }
        guard systemAudio && microphone else {
            write(converted)
            return
        }
        mixer.add(converted.samples, source: source, at: converted.time)
        while let mixed = mixer.mix() { write(mixed) }
    }

    private func write(_ sound: (samples: [Float], time: Double)) {
        writer.appendAudio(samples: sound.samples, channels: VideoEncoderSettings.audioChannels,
                           sampleRate: VideoEncoderSettings.audioSampleRate,
                           at: CMTime(seconds: sound.time, preferredTimescale: 48_000))
    }
}

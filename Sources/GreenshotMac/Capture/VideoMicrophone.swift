// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import GreenshotCore

private let log = Log("Video")

enum MicrophoneError: LocalizedError {
    case noMicrophone
    case cannotUse

    var errorDescription: String? {
        switch self {
        case .noMicrophone: return "This Mac has no microphone."
        case .cannotUse: return "The microphone could not be used."
        }
    }
}

/// The default microphone for a recording (upstream `WasapiAudioCaptureProvider` with `AudioCaptureSource.Microphone`),
/// through AVCaptureSession on every macOS version, its buffers' times moved to the host clock the screen uses.
final class MicrophoneCapture: NSObject, RecordingAudioProvider, AVCaptureAudioDataOutputSampleBufferDelegate,
                               @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Greenshot microphone")
    private var handler: (@Sendable (CMSampleBuffer, CMTime) -> Void)?

    func start(_ handler: @escaping @Sendable (CMSampleBuffer, CMTime) -> Void) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else { throw MicrophoneError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw MicrophoneError.cannotUse
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        output.setSampleBufferDelegate(self, queue: queue)
        queue.async { [self] in
            self.handler = handler
            session.startRunning()
        }
        log.info("Recording the microphone \(device.localizedName)")
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let host = CMClockGetHostTimeClock()
        let clock = session.synchronizationClock ?? host
        handler(sampleBuffer, CMSyncConvertTime(time, from: clock, to: host))
    }

    /// Whether the microphone may be recorded; the first time macOS asks.
    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
}

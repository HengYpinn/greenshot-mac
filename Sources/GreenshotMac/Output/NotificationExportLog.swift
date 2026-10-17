// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore

private let log = Log("Notifications")

/// Collects how every destination of one capture ended, for one notification after the capture: upstream's export log
/// (`Greenshot.Base/Recipes/Pipeline/ExportOutcome.cs` `ExportLog`) and Notification step (`ExportNotification`).
/// `OutputManager.handle` asks for one completion per destination (or one for the picker, whose result names the
/// picked entry), then closes the log; once every completion came, the notification is shown.
@MainActor
final class NotificationExportLog {
    /// How long an open log holds back the information messages of the destinations at most: a destination that never
    /// calls back must not silence the messages for the rest of the session. A late result still gets its notification.
    static let holdBackLimit: TimeInterval = 5 * 60

    private static var openSince: [ObjectIdentifier: Date] = [:]

    /// True while the exports of a capture run: their own information messages ("Saved …", "Copied …") wait for the
    /// one notification after the capture. Warnings and errors still show at once.
    static var isCollecting: Bool {
        let limit = Date().addingTimeInterval(-holdBackLimit)
        openSince = openSince.filter { $0.value > limit }
        return !openSince.isEmpty
    }

    private let capture: Capture
    private let settings: SettingsStore
    /// One slot per expected export, in the order of the destinations.
    private var results: [ExportResult?] = []
    private var closed = false
    private var finished = false

    init(capture: Capture, settings: SettingsStore) {
        self.capture = capture
        self.settings = settings
        Self.openSince[ObjectIdentifier(self)] = Date()
    }

    /// The completion for one export of the capture.
    func expect() -> ExportCompletion {
        let slot = results.count
        results.append(nil)
        var called = false
        return { [self] result in
            // The contract is once; a second call changes nothing.
            guard !called else { return }
            called = true
            results[slot] = result
            finishIfDone()
        }
    }

    /// All exports are started: the notification is shown once they all ended.
    func close() {
        closed = true
        finishIfDone()
    }

    private func finishIfDone() {
        guard closed, !finished, !results.contains(where: { $0 == nil }) else { return }
        finished = true
        Self.openSince[ObjectIdentifier(self)] = nil
        let exports = results.compactMap { $0 }
        let capture = capture
        let values = settings.value
        // Nothing to show: no need to look for codes (macOS notifications turned off, or the level None).
        guard values.showNotifications, values.notificationLevel != .none, NotificationService.shared.state != .off else { return }
        // Upstream's ZXing processor adds the codes of every region capture while `ScanOnCapture` is on.
        guard values.scanQRCodesOnCapture else {
            NotificationService.shared.showExports(exports, of: capture, barcodes: [])
            return
        }
        let image = capture.image
        DispatchQueue.global(qos: .userInitiated).async {
            let codes: [NotificationBarcode]
            do {
                codes = try BarcodeDetector.detect(in: image).map(NotificationBarcode.init)
            } catch {
                log.warn("Couldn't look for QR codes for the notification.", error: error)
                codes = []
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NotificationService.shared.showExports(exports, of: capture, barcodes: codes)
                }
            }
        }
    }
}

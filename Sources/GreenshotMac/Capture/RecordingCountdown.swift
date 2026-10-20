// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The seconds before a recording starts, big in the middle of what will be recorded (upstream's recipe step waits
/// `DelayMs` without showing it). The panel takes no clicks and is gone before the recording starts.
@MainActor
final class RecordingCountdown {
    private var panel: NSPanel?
    private var timer: Timer?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var remaining = 0
    private var view: RecordingCountdownView?
    private var tick: ((Int) -> Void)?
    /// Cancelled after it ran out, while the panel goes off the screen: the recording doesn't start after all.
    private var cancelledAtTheEnd = false

    /// Counts `seconds` down over `area` (Quartz global points); `tick` gets the seconds left. True when it ran out,
    /// false when it was cancelled.
    func run(seconds: Int, over area: CGRect, tick: @escaping (Int) -> Void) async -> Bool {
        remaining = max(seconds, 1)
        cancelledAtTheEnd = false
        self.tick = tick
        let view = RecordingCountdownView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        view.seconds = remaining
        self.view = view
        let appKitArea = Geometry.quartzRect(fromAppKit: area, primaryScreenHeight: ScreenSpace.primaryScreenHeight)
        let frame = NSRect(x: appKitArea.midX - 80, y: appKitArea.midY - 80, width: 160, height: 160)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        tick(remaining)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.second() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func cancel() {
        end(false)
    }

    private func second() {
        remaining -= 1
        if remaining <= 0 {
            end(true)
        } else {
            view?.seconds = remaining
            tick?(remaining)
        }
    }

    private func end(_ ranOut: Bool) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        guard let continuation else {
            // The countdown ran out a moment ago and the answer is still on its way: a cancel now still counts.
            if !ranOut { cancelledAtTheEnd = true }
            return
        }
        self.continuation = nil
        // A moment for the window server to take the panel off the screen before the first frame.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            continuation.resume(returning: ranOut && !(self?.cancelledAtTheEnd ?? false))
        }
    }
}

/// The number of the countdown on a dark rounded square.
final class RecordingCountdownView: NSView {
    var seconds = 3 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).fill()
        let number = NSAttributedString(string: "\(seconds)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 88, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let size = number.size()
        number.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + 10))
        let text = String(localized: "Recording starts", comment: "Below the countdown's seconds")
        func captionText(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.85),
            ])
        }
        // Longer languages get a smaller font, so the caption keeps its margins.
        var caption = captionText(13)
        let room = bounds.width - 36
        if caption.size().width > room { caption = captionText(max(9, floor(13 * room / caption.size().width))) }
        let captionSize = caption.size()
        caption.draw(at: NSPoint(x: bounds.midX - captionSize.width / 2, y: bounds.minY + 18))
    }
}

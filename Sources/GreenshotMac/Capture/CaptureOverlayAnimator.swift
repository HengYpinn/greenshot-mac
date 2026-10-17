// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Redraws the capture screen about 60 times a second while something moves. A drawing that still moves asks for the
/// next frame with `requestFrame()`; without a request the timer stops.
@MainActor
final class CaptureOverlayAnimator {
    private var timer: Timer?
    private var requested = false
    private let tick: () -> Void

    init(tick: @escaping () -> Void) {
        self.tick = tick
    }

    func requestFrame() {
        requested = true
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        guard requested else {
            stop()
            return
        }
        requested = false
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        requested = false
    }
}

/// The selection's movement (upstream `CaptureWindow.xaml.cs` `ShowSelection`, `AnimateSelection`, `SelectionChanged`):
/// in window mode it slides from window to window, grows out of the mouse when the mode starts and shrinks into it when
/// the mode ends; its labels fade in. The panels avoid the selection once it stayed the same for a moment.
extension CaptureOverlayController {
    /// The selection as drawn now: on its way while it slides, else `selection`. Capturing always uses `selection`.
    func displayedSelection(at now: Date) -> CGRect? {
        guard let motion = selectionMotion, !motion.isFinished(at: now) else { return selection }
        return mode == .window || selection == nil ? motion.value(at: now) : selection
    }

    /// The selection slides now.
    func selectionMoves(at now: Date) -> Bool {
        guard let motion = selectionMotion else { return false }
        return !motion.isFinished(at: now) && (mode == .window || selection == nil)
    }

    /// The opacity of the selection's labels: window selections fade them in after they moved.
    func labelsOpacity(at now: Date) -> CGFloat {
        guard mode == .window, let start = labelsAppearedAt else { return 1 }
        return CaptureAnimation.labelsOpacity(after: now.timeIntervalSince(start))
    }

    /// The selection stayed the same for `CaptureAnimation.selectionSettleTime` (always in the snapshots).
    func selectionSettled(at now: Date) -> Bool {
        !isShown || now.timeIntervalSince(selectionChangedAt) >= CaptureAnimation.selectionSettleTime
    }

    func modeWillChange(from old: Mode, to new: Mode) {
        guard animates else { return }
        let now = Date()
        if old == .window, let shown = displayedSelection(at: now) {
            // Shrinks into the mouse (upstream `WindowCaptureTool.Deactivate`).
            selectionMotion = CaptureMotion(from: shown, to: CGRect(origin: cursor, size: .zero), start: now,
                                            duration: CaptureAnimation.selectionDuration)
        }
        if new == .window { growsFromCursor = true }
    }

    /// After `updateSelection` changed the selection.
    func selectionDidChange(from previous: CGRect?) {
        let now = Date()
        selectionChangedAt = now
        guard isShown else { return }
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: CaptureAnimation.selectionSettleTime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
        guard animates, mode == .window, let target = selection else { return }
        let start = growsFromCursor ? CGRect(origin: cursor, size: .zero) : (displayedSelectionBefore(now) ?? previous ?? target)
        growsFromCursor = false
        selectionMotion = CaptureMotion(from: start, to: target, start: now, duration: CaptureAnimation.selectionDuration)
        labelsAppearedAt = now
        animator.requestFrame()
    }

    /// Where the sliding selection is now, before it gets its new target.
    private func displayedSelectionBefore(_ now: Date) -> CGRect? {
        guard let motion = selectionMotion, !motion.isFinished(at: now) else { return nil }
        return motion.value(at: now)
    }

    func stopMoving() {
        animator.stop()
        settleTimer?.invalidate()
        settleTimer = nil
    }
}

/// The panels' movement (upstream `CaptureWindow.xaml.cs` `PlacePanel`, `MovePanel`, `Fade`, `UpdatePanelSize`): a panel
/// slides to a new corner, fades in when shown and out when hidden; the info panel only grows while it is shown.
extension OverlayMarksView {
    /// Places and draws the panels, avoiding `avoidLoosely` (the selection, once it settled). Returns their places.
    func placeAndDrawPanels(_ panels: [OverlayPanel], cursor: CGPoint, avoidLoosely: [CGRect], now: Date,
                            in context: CGContext) -> [CGRect] {
        guard let controller else { return [] }
        let animates = controller.animates
        var placed: [CGRect] = []
        var targets: [String: CGRect] = [:]
        var drawn: [String: (panel: OverlayPanel, frame: CGRect)] = [:]
        for panel in panels {
            let size = panel.growsOnly ? CaptureAnimation.grownSize(panelSizes[panel.id], panel.size) : panel.size
            panelSizes[panel.id] = size
            let current = panelFrames[panel.id]
            let box = CapturePanelPlacement.place(size: size, monitor: bounds, cursor: cursor, current: current, avoid: placed,
                                                  avoidLoosely: avoidLoosely)
            placed.append(box)
            targets[panel.id] = box
            var frame = box
            var alpha: CGFloat = 1
            if animates {
                if let current, box != current {
                    // Growing in its corner doesn't slide, a move to another place does.
                    if box == CapturePanelPlacement.resize(current, to: size, in: bounds) {
                        panelMotions[panel.id] = nil
                    } else {
                        let from = panelMotions[panel.id].map { $0.value(at: now) } ?? drawnPanels[panel.id]?.frame ?? current
                        panelMotions[panel.id] = CaptureMotion(from: CGRect(origin: from.origin, size: size), to: box, start: now,
                                                               duration: CaptureAnimation.panelMoveDuration)
                    }
                }
                if current == nil, fadingPanels[panel.id] == nil { panelAppearedAt[panel.id] = now }
                fadingPanels[panel.id] = nil
                if let motion = panelMotions[panel.id] {
                    if motion.isFinished(at: now) {
                        panelMotions[panel.id] = nil
                    } else {
                        frame = motion.value(at: now)
                        controller.animator.requestFrame()
                    }
                }
                if let appeared = panelAppearedAt[panel.id] {
                    alpha = CGFloat(CaptureAnimation.progress(from: appeared, to: now, duration: CaptureAnimation.panelFadeDuration))
                    if alpha < 1 { controller.animator.requestFrame() } else { panelAppearedAt[panel.id] = nil }
                }
            }
            draw(panel, in: frame, alpha: alpha, context: context)
            drawn[panel.id] = (panel, frame)
        }
        // Hidden panels give their place free at once and fade out.
        for (id, last) in drawnPanels where drawn[id] == nil {
            panelSizes[id] = nil
            panelMotions[id] = nil
            panelAppearedAt[id] = nil
            if animates { fadingPanels[id] = (last.panel, last.frame, now) }
        }
        for (id, fading) in fadingPanels {
            let alpha = 1 - CGFloat(CaptureAnimation.progress(from: fading.start, to: now, duration: CaptureAnimation.panelFadeDuration))
            if alpha <= 0 {
                fadingPanels[id] = nil
            } else {
                draw(fading.panel, in: fading.frame, alpha: alpha, context: context)
                controller.animator.requestFrame()
            }
        }
        drawnPanels = drawn
        panelFrames = targets
        return placed
    }

    /// Forgets the panels: the mouse left this display.
    func resetPanels() {
        panelFrames = [:]
        panelMotions = [:]
        panelAppearedAt = [:]
        panelSizes = [:]
        drawnPanels = [:]
        fadingPanels = [:]
    }

    private func draw(_ panel: OverlayPanel, in frame: CGRect, alpha: CGFloat, context: CGContext) {
        guard alpha < 1 else {
            panel.draw(frame)
            return
        }
        context.saveGState()
        context.setAlpha(max(alpha, 0))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        panel.draw(frame)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

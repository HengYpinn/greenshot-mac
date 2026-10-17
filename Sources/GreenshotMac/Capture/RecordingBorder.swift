// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The frame around what is recorded: the RecordVideo step's `ShowCaptureBorder` (upstream `RecordVideoRecipeStep.cs:70,342`).
/// Upstream asks Windows for its yellow capture border (`IGraphicsCaptureSession3.IsBorderRequired`,
/// `Greenshot.Base/Video/WindowsGraphicsCaptureVideoSession.cs:403`); ScreenCaptureKit has none, so Greenshot draws a yellow
/// frame itself, in panels that take no clicks, one per display (`RecordingBorderGeometry`).
///
/// The recording leaves the panels out: a display or region recording by their window ids
/// (`VideoRecorder.start(_:excludingWindows:)`, so the panels must be on the screen before it starts), a window
/// recording sees only its window anyway. The frame follows a recorded window every half second and is gone while the
/// window isn't on the screen.
@MainActor
final class RecordingBorder {
    private let target: VideoCaptureTarget
    private var panels: [NSPanel] = []
    private var timer: Timer?

    init(target: VideoCaptureTarget) {
        self.target = target
    }

    /// The window ids of the panels on the screen, for the recording to leave out.
    var windowIDs: [CGWindowID] {
        panels.filter { $0.isVisible && $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) }
    }

    /// Shows the frame; a window's frame follows the window until `hide`.
    func show() {
        layout()
        guard target.isWindow, timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    /// The panels for where the recorded area is now; the ones there already are moved.
    private func layout() {
        let displays = NSScreen.screens.map { (id: $0.displayID, frame: CGDisplayBounds($0.displayID)) }
        var windowFrame: CGRect?
        if case .window(let id) = target { windowFrame = Self.onScreenFrame(of: id) }
        let area = RecordingBorderGeometry.recordedArea(of: target, displays: displays, windowFrame: windowFrame)
        let pieces = area.map { RecordingBorderGeometry.pieces(around: $0, displays: displays.map(\.frame)) } ?? []
        while panels.count > pieces.count {
            panels.removeLast().orderOut(nil)
        }
        for (index, piece) in pieces.enumerated() {
            if index == panels.count { panels.append(Self.makePanel()) }
            Self.place(panels[index], piece: piece)
        }
    }

    private static func place(_ panel: NSPanel, piece: RecordingBorderGeometry.Piece) {
        let frame = Geometry.quartzRect(fromAppKit: piece.frame, primaryScreenHeight: ScreenSpace.primaryScreenHeight)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        (panel.contentView as? RecordingBorderView)?.piece = piece
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = RecordingBorderView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        return panel
    }

    /// The window's frame in Quartz global points while it is on the screen; nil when it is minimised, on another
    /// Space, hidden or gone.
    private static func onScreenFrame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == id }),
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }
}

/// One display's part of the frame: the panel filled yellow outside `piece.hole`.
final class RecordingBorderView: NSView {
    var piece: RecordingBorderGeometry.Piece? {
        didSet { if piece != oldValue { needsDisplay = true } }
    }

    /// Top left origin, like the piece's hole.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let piece else { return }
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: piece.hole))
        path.windingRule = .evenOdd
        NSColor.systemYellow.setFill()
        path.fill()
    }
}

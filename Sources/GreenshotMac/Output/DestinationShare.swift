// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The macOS share menu with the screenshot (AirDrop, Messages, Notes, …): the Mac's counterpart of upstream
/// `Greenshot/Destinations/Win10ShareDestination.cs`. The image is shared as a file, which every service takes.
@MainActor
final class ShareDestination: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    /// The share in progress, kept alive (with its anchor window) until a service was chosen and finished.
    private static var current: ShareDestination?

    private let picker: NSSharingServicePicker
    private var anchorWindow: NSWindow?
    private weak var sourceWindow: NSWindow?

    private init(file: URL) {
        picker = NSSharingServicePicker(items: [file])
        super.init()
        picker.delegate = self
    }

    /// Shows the share menu under the top of `window` (an editor), or at the mouse.
    static func share(_ capture: Capture, settings: SettingsStore, window: NSWindow?) {
        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be shared")
            return
        }
        current?.close()
        let share = ShareDestination(file: file)
        current = share
        share.show(over: window)
    }

    private func show(over window: NSWindow?) {
        NSApp.activate()
        if let window, let view = window.contentView {
            sourceWindow = window
            let anchor = NSRect(x: view.bounds.midX - 1, y: view.bounds.maxY - 2, width: 2, height: 2)
            picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
            return
        }
        // Without a window, a tiny transparent one at the mouse holds the menu.
        let mouse = NSEvent.mouseLocation
        let anchor = NSWindow(contentRect: NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .floating
        anchor.isReleasedWhenClosed = false
        anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        anchor.orderFrontRegardless()
        anchorWindow = anchor
        sourceWindow = anchor
        guard let view = anchor.contentView else { return }
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        // Cancelled: nothing more comes. Otherwise the service calls back when it is done.
        if service == nil { close() }
    }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sourceWindow
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        close()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        close()
        let nsError = error as NSError
        guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else { return }
        ErrorPresenter.show(error, title: "The screenshot could not be shared")
    }

    private func close() {
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
        if Self.current === self { Self.current = nil }
    }
}

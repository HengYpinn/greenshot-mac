// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UserNotifications

private let log = Log("Notifications")

/// Whether and how the app can notify, for Settings › Capture › Notifications.
enum NotificationState: Equatable {
    /// No app bundle (`swift run`): the in-app panel shows the messages.
    case inApp
    /// macOS refused notifications for this build: the in-app panel shows the messages.
    case refused
    /// macOS hasn't asked the user yet; it asks with the first notification.
    case notAsked
    case allowed
    /// Turned off in System Settings: nothing is shown (upstream: the balloons don't take over).
    case off
}

/// How the app tells the user what happened: port of upstream's `INotificationService` and
/// `Greenshot/Shell/NotificationServiceFactory.cs`. The first available of two providers, picked at launch: macOS
/// notifications (upstream's toasts, `Greenshot/Native/ToastNotificationService.cs`) when the app runs from its bundle,
/// else the in-app panel (`ToastPanel`, upstream's tray balloons). See docs/notifications.md upstream.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// Posted when `state` may have changed.
    static let stateDidChange = Notification.Name("GreenshotNotificationStateDidChange")

    /// True when the notification after a capture can show it and offer it again on a click, also after a restart
    /// (upstream `ShowsCaptures`): macOS notifications are available and not turned off for the app.
    static var showsCaptures: Bool {
        switch shared.state {
        case .allowed, .notAsked: return true
        case .inApp, .refused, .off: return false
        }
    }

    private(set) weak var app: AppDelegate?
    /// The macOS notifications; nil without an app bundle.
    private(set) var native: NativeNotifications?

    var state: NotificationState { native?.state ?? .inApp }

    /// Called while the app finishes launching (before `applicationDidFinishLaunching` returns), so the click on a
    /// notification that launched the app reaches the delegate.
    static func install(app: AppDelegate) {
        shared.install(app: app)
    }

    private func install(app: AppDelegate) {
        self.app = app
        guard NativeNotifications.isAvailable, let bundleIdentifier = Bundle.main.bundleIdentifier,
              let store = NotificationCaptureStore.inCaches(bundleIdentifier: bundleIdentifier) else {
            log.info("Not running from an app bundle: messages appear in the in-app panel.")
            return
        }
        let native = NativeNotifications(store: store)
        self.native = native
        native.install()
    }

    // MARK: Messages

    /// A message (upstream `ShowInfoMessage` / `ShowWarningMessage` / `ShowErrorMessage`). The caller filtered by the
    /// level already. While the exports of a capture are collected, information about them waits for the one
    /// notification after the capture.
    func message(_ text: String, detail: String?, kind: MessageKind, action: (() -> Void)?, onClosed: (() -> Void)?) {
        if kind == .info, NotificationExportLog.isCollecting {
            log.debug("Left to the notification after the capture: \(text)")
            onClosed?()
            return
        }
        guard let native else {
            ToastPanel.show(title: text, lines: detail.map { [$0] } ?? [], kind: kind, action: action, onClosed: onClosed)
            return
        }
        native.postMessage(title: text, body: detail, kind: kind, action: action, onClosed: onClosed) {
            ToastPanel.show(title: text, lines: detail.map { [$0] } ?? [], kind: kind, action: action, onClosed: onClosed)
        }
    }

    /// The notification after a capture: one for all its exports and the barcodes found in it (upstream
    /// `ExportNotification.ShowAsync`).
    func showExports(_ exports: [ExportResult], of capture: Capture, barcodes: [NotificationBarcode]) {
        guard let settings = app?.settings.value,
              let content = NotificationSummary.make(title: capture.title, exports: exports, barcodes: barcodes, settings: settings) else {
            return
        }
        let fallback = {
            // Like upstream's balloon: the text of all rows, a click opens the upload or the saved file.
            ToastPanel.show(title: content.title, lines: content.lines, kind: content.kind,
                            action: content.opens.map { url in { Self.open(url) } })
        }
        guard let native else {
            fallback()
            return
        }
        native.postSummary(content, capture: capture, thumbnail: settings.showNotificationThumbnail, fallback: fallback)
    }

    private static func open(_ url: URL) {
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if NotificationSummary.isWebLink(url.absoluteString) {
            // A link comes from a server or a command's output: only a web page opens, never smb: or an app's scheme.
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Clicks

    /// A click on a notification or one of its buttons, also when macOS launched the app for it.
    func handle(_ click: NotificationClick) {
        guard let native else { return }
        let payload = click.payload
        switch click.action {
        case UNNotificationDefaultActionIdentifier:
            if payload.captureId != nil {
                // Upstream `CaptureActivated`: the destination picker offers the kept capture again.
                guard let app, let capture = native.captures.take(payload) else {
                    log.info("The capture of the clicked notification is gone (kept for an hour).")
                    return
                }
                // A changed built-in `recipe_notification` takes it (RSTEPS).
                if RecipeRuntime.shared?.offerNotificationCapture(capture) == true { return }
                app.output.showPicker(for: capture)
            } else {
                native.runClickAction(of: click.identifier)
            }
        case UNNotificationDismissActionIdentifier:
            native.captures.discard(payload.captureId)
            native.runClosedAction(of: click.identifier)
        case NotificationAction.edit.rawValue:
            guard let app, let capture = native.captures.take(payload) else {
                log.info("The capture of the notification is gone (kept for an hour).")
                return
            }
            app.editors.open(capture)
        case NotificationAction.showInFolder.rawValue:
            native.captures.discard(payload.captureId)
            if let file = payload.existingSavedFile() {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                log.warn("Ignoring Show in Finder for a file that isn't there.")
            }
        case NotificationAction.copyLink.rawValue:
            native.captures.discard(payload.captureId)
            copyLink(from: payload.webLinks)
        default:
            log.warn("Ignoring the notification action \(click.action).")
        }
    }

    /// Copies the link; with several a menu at the mouse chooses which (upstream's drop-down above the buttons).
    private func copyLink(from links: [NotificationLink]) {
        guard links.count > 1 else {
            if let link = links.first { Clipboard.copy(text: link.value) }
            return
        }
        let menu = NSMenu(title: NotificationAction.copyLink.title)
        menu.autoenablesItems = false
        let header = NSMenuItem(title: NotificationAction.copyLink.title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for link in links {
            menu.addItem(ClosureMenuItem(title: FilenamePattern.menuTitle(link.text, length: 80)) {
                Clipboard.copy(text: link.value)
            })
        }
        NSApp.activate()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A click on a notification, as plain values: the notification's id, the action (a button, the click itself or the
/// dismissal) and what it carries.
struct NotificationClick: Sendable {
    var identifier: String
    var action: String
    var payload: NotificationPayload
}

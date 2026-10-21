// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers
import UserNotifications

private let log = Log("Notifications")

/// macOS notifications: the Mac's form of upstream's toasts (`Greenshot/Native/ToastNotificationService.cs`). macOS
/// asks the user once; while the notifications are turned off for the app nothing is shown and nothing is kept
/// (upstream "Turned off by the user or a policy"), and Focus holds them back like those of any app.
@MainActor
final class NativeNotifications {
    /// `UNUserNotificationCenter` only works in a process with an app bundle (it throws without one).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// The category of a plain message: no buttons, but the dismissal comes back for its closed callback.
    static let messageCategory = "message"

    /// How it may post right now.
    enum Permission {
        case allowed
        /// Turned off by the user: nothing is shown.
        case off
        /// macOS refused this build: the in-app panel takes over.
        case unavailable
    }

    let captures: NotificationCaptures
    private let center: UNUserNotificationCenter
    private let delegate = NotificationCenterDelegate()
    private var status: UNAuthorizationStatus = .notDetermined
    /// Banners or alerts appear on the screen: not the style None, not only in Notification Center.
    private var alertsAppear = true
    /// `requestAuthorization` failed: macOS doesn't let this build notify (not a choice of the user).
    private var refused = false
    private var asking = false
    private var waiting: [(Permission) -> Void] = []
    /// The click and closed actions of plain messages, by notification id; they only live while the app runs (upstream
    /// keeps them in memory too).
    private var actions: [String: (click: (() -> Void)?, closed: (() -> Void)?, date: Date)] = [:]
    private var cleanupTimer: Timer?

    init(store: NotificationCaptureStore) {
        captures = NotificationCaptures(store: store)
        center = UNUserNotificationCenter.current()
    }

    var state: NotificationState {
        if refused { return .refused }
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .off
        case .notDetermined: return .notAsked
        @unknown default: return .off
        }
    }

    func install() {
        center.delegate = delegate
        center.setNotificationCategories(Self.categories())
        refreshStatus()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        // After a click that launched the app was handled (its capture may be older than an hour), then every 10 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.removeExpired() }
        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeExpired() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    /// The buttons of the notifications after a capture: one category per combination, registered before any is used
    /// (macOS applies a category set right before a post late). Each lets the dismissal through, which discards the
    /// capture at once.
    private static func categories() -> Set<UNNotificationCategory> {
        var categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: messageCategory, actions: [], intentIdentifiers: [], options: [.customDismissAction]),
        ]
        for combination in NotificationAction.allCombinations {
            guard let identifier = NotificationAction.categoryIdentifier(for: combination) else { continue }
            let actions = combination.map { action in
                UNNotificationAction(identifier: action.rawValue, title: action.title, options: [.foreground])
            }
            categories.insert(UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [],
                                                     options: [.customDismissAction]))
        }
        return categories
    }

    // MARK: Permission

    /// Asks macOS for the current setting (turning notifications on in System Settings works without a restart).
    func refreshStatus(then done: (() -> Void)? = nil) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let appear = settings.alertSetting == .enabled && settings.alertStyle != .none
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.alertsAppear = appear
                    self.update(status)
                    done?()
                }
            }
        }
    }

    private func update(_ status: UNAuthorizationStatus) {
        guard status != self.status else { return }
        self.status = status
        log.info("macOS notifications: \(state)")
        NotificationCenter.default.post(name: NotificationService.stateDidChange, object: nil)
    }

    /// Calls `body` with whether it may post now; the first time macOS asks the user, and `body` waits for the answer.
    func whenAllowed(_ body: @escaping (Permission) -> Void) {
        guard !refused else {
            body(.unavailable)
            return
        }
        refreshStatus {
            switch self.status {
            case .authorized, .provisional, .ephemeral: body(.allowed)
            case .notDetermined: self.requestPermission(then: body)
            default: body(.off)
            }
        }
    }

    /// Asks the user (only does something while macOS hasn't asked yet).
    func requestPermission(then body: ((Permission) -> Void)? = nil) {
        if let body { waiting.append(body) }
        guard !asking else { return }
        asking = true
        center.requestAuthorization(options: [.alert]) { granted, error in
            let message = error.map { String(describing: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.asking = false
                    if let message, !granted {
                        self.refused = true
                        log.error("macOS doesn't let this build post notifications; messages appear in the in-app panel: \(message)")
                        NotificationCenter.default.post(name: NotificationService.stateDidChange, object: nil)
                    }
                    self.update(granted ? .authorized : (self.refused ? .notDetermined : .denied))
                    let permission: Permission = granted ? .allowed : (self.refused ? .unavailable : .off)
                    let callbacks = self.waiting
                    self.waiting = []
                    callbacks.forEach { $0(permission) }
                }
            }
        }
    }

    // MARK: Posting

    /// A plain message; `fallback` shows it in the panel when macOS refused this build.
    func postMessage(title: String, body: String?, kind: MessageKind, action: (() -> Void)?, onClosed: (() -> Void)?,
                     fallback: @escaping () -> Void) {
        whenAllowed { permission in
            switch permission {
            case .unavailable:
                fallback()
            case .off:
                onClosed?()
            case .allowed:
                self.addMessage(title: title, body: body, kind: kind, action: action, onClosed: onClosed)
            }
        }
    }

    /// A message the user must see: a notification when they are on, else `fallback` (the in-app panel), also when
    /// they are turned off. It never makes macOS ask for the permission, whose question would come next to whatever
    /// the message is about (e.g. macOS's Screen Recording prompt).
    func postMessageWithoutAsking(title: String, body: String?, kind: MessageKind, action: (() -> Void)?,
                                  onClosed: (() -> Void)?, fallback: @escaping () -> Void) {
        guard !refused else {
            fallback()
            return
        }
        refreshStatus {
            // Only a notification that appears on the screen: provisional ones go quietly to Notification Center, and
            // the style None or alerts switched off show nothing. A Focus can still hold one back; the app can't tell.
            let appears = self.status == .authorized && self.alertsAppear
            if appears {
                self.addMessage(title: title, body: body, kind: kind, action: action, onClosed: onClosed)
            } else {
                fallback()
            }
        }
    }

    private func addMessage(title: String, body: String?, kind: MessageKind, action: (() -> Void)?, onClosed: (() -> Void)?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body ?? ""
        content.categoryIdentifier = Self.messageCategory
        if kind != .info, let icon = statusIconAttachment(kind) { content.attachments = [icon] }
        let identifier = UUID().uuidString
        pruneActions()
        if action != nil || onClosed != nil { actions[identifier] = (action, onClosed, Date()) }
        add(identifier, content)
    }

    /// The notification after a capture: keeps the capture for a click (only while notifications are shown), with its
    /// thumbnail when the setting is on (upstream `ExportNotification.ShowAsync` with `NotificationCaptures`).
    func postSummary(_ summary: NotificationSummaryContent, capture: Capture, thumbnail: Bool, fallback: @escaping () -> Void) {
        whenAllowed { permission in
            switch permission {
            case .unavailable:
                fallback()
            case .off:
                log.debug("Notifications are off for the app: nothing shown, nothing kept.")
            case .allowed:
                var summary = summary
                // What went to the destinations is kept; codes alone (every export declined) keep nothing.
                if summary.hasExports { summary.captureId = NotificationCaptureStore.newId() }
                self.post(summary, capture: capture, thumbnail: thumbnail)
            }
        }
    }

    private func post(_ summary: NotificationSummaryContent, capture: Capture, thumbnail: Bool) {
        let payload = NotificationPayload(captureId: summary.captureId, savedFile: summary.savedFile?.path, links: summary.links,
                                          title: capture.title, date: capture.date)
        let identifier = summary.captureId ?? UUID().uuidString
        let send = { (picture: UNNotificationAttachment?) in
            let content = UNMutableNotificationContent()
            content.title = summary.title
            content.body = summary.body
            content.categoryIdentifier = summary.categoryIdentifier ?? Self.messageCategory
            content.userInfo = payload.userInfo
            // The thumbnail, else the warning or error sign.
            if let picture = picture ?? (summary.kind == .info ? nil : self.statusIconAttachment(summary.kind)) {
                content.attachments = [picture]
            }
            self.add(identifier, content) { self.keep(capture, id: summary.captureId) }
        }
        guard thumbnail, let attachmentURL = summary.captureId.flatMap(captures.store.attachmentURL) else {
            send(nil)
            return
        }
        // Only the thumbnail before the notification, the capture after it (upstream: nothing delays the toast).
        let image = capture.image
        let folder = captures.store.folder
        DispatchQueue.global(qos: .userInitiated).async {
            let written = Self.writeThumbnail(of: image, to: attachmentURL, folder: folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { send(written ? Self.attachment(attachmentURL) : nil) }
            }
        }
    }

    private func keep(_ capture: Capture, id: String?) {
        guard let id else { return }
        captures.keep(capture, id: id) { [weak self] in self?.removeExpired() }
    }

    private nonisolated static func writeThumbnail(of image: CGImage, to url: URL, folder: URL) -> Bool {
        guard let thumbnail = NotificationThumbnail.make(image) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ImageExporter.write(thumbnail, to: url, format: .png)
            return true
        } catch {
            log.warn("Couldn't write the thumbnail for the notification.", error: error)
            return false
        }
    }

    /// macOS moves the file into its own store.
    private static func attachment(_ url: URL) -> UNNotificationAttachment? {
        do {
            return try UNNotificationAttachment(identifier: url.lastPathComponent, url: url,
                                                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
        } catch {
            log.warn("Couldn't attach \(url.lastPathComponent) to the notification.", error: error)
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// The warning or error sign as the notification's picture, like upstream's toasts show Windows' error or warning
    /// icon as their big image (`StatusIcons`). macOS shows the app's icon itself.
    private func statusIconAttachment(_ kind: MessageKind) -> UNNotificationAttachment? {
        guard let data = Self.statusIconPNG(kind), let url = captures.store.attachmentURL(NotificationCaptureStore.newId()) else { return nil }
        do {
            try FileManager.default.createDirectory(at: captures.store.folder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            log.warn("Couldn't write the icon for the notification.", error: error)
            return nil
        }
        return Self.attachment(url)
    }

    static func statusIconPNG(_ kind: MessageKind, pixels: Int = 192) -> Data? {
        guard let symbol = ToastPanel.icon(for: kind, pointSize: CGFloat(pixels) / 2),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let side = CGFloat(pixels)
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = symbol.size
        let scale = min(side * 0.8 / max(size.width, 1), side * 0.8 / max(size.height, 1))
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        symbol.draw(in: NSRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func add(_ identifier: String, _ content: UNNotificationContent, then done: (() -> Void)? = nil) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            let message = error.map { String(describing: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let message {
                        log.error("Couldn't post the notification: \(message)")
                        self.actions[identifier] = nil
                        return
                    }
                    done?()
                }
            }
        }
    }

    // MARK: Clicks and cleanup

    func runClickAction(of identifier: String) {
        guard let entry = actions.removeValue(forKey: identifier) else { return }
        entry.click?()
        entry.closed?()
    }

    func runClosedAction(of identifier: String) {
        actions.removeValue(forKey: identifier)?.closed?()
    }

    private func pruneActions() {
        let limit = Date().addingTimeInterval(-NotificationCaptureStore.lifetime)
        actions = actions.filter { $0.value.date > limit }
    }

    /// A notification after a capture lives an hour, like upstream's toasts: older ones leave Notification Center and
    /// their captures are removed (upstream `RemoveUnused`, which keeps a younger capture for a click on its way).
    func removeExpired() {
        pruneActions()
        let limit = Date().addingTimeInterval(-NotificationCaptureStore.lifetime)
        center.getDeliveredNotifications { delivered in
            let expired = delivered.filter { note in
                note.date < limit && note.request.content.categoryIdentifier.hasPrefix("capture.")
            }.map(\.request.identifier)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if !expired.isEmpty {
                        self.center.removeDeliveredNotifications(withIdentifiers: expired)
                        log.debug("Removed \(expired.count) notifications older than an hour.")
                    }
                    self.captures.removeExpiredFiles()
                }
            }
        }
    }
}

/// The notification centre's delegate: hands clicks to the app on the main thread and shows notifications also while
/// the app is in front (an editor window), where macOS would hold them back.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let click = NotificationClick(identifier: request.identifier, action: response.actionIdentifier,
                                      payload: NotificationPayload(userInfo: request.content.userInfo))
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NotificationService.shared.handle(click) }
            completionHandler()
        }
    }
}

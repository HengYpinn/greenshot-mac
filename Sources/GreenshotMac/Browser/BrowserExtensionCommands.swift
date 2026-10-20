// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The browser extension's commands HANDSHAKE, IMPORT_CAPTURE and TAB_CHANGED (upstream
/// `Ipc/BrowserExtension/BrowserExtensionIpcExtension.cs`), registered with `sources: [.nativeMessaging]`: only
/// greenshot-native-host may send them. Every request is checked first: the extension switched on in Settings, and the
/// origin from the host's HELLO allowed (upstream checks it once per connection in `ExtensionOriginPolicy`).
@MainActor
enum BrowserExtensionCommands {
    private nonisolated static let log = Log("Browser")
    /// The installed host manifests' lists, read again only when a manifest changes.
    private nonisolated static let originGate = BrowserOriginGate()

    static func register(in table: IPCCommandTable, app: AppDelegate) {
        let version = AutomationCommands.appVersion
        table.register(BrowserCommand.handshake, sources: [.nativeMessaging]) { [app] context in
            if let refusal = await refusal(of: context, app: app) { return .error(refusal) }
            log.info("Browser extension connected (\(BrowserText.browserName(context.envelope.extra["browser"]?.stringValue, origin: context.origin) ?? "unknown browser"), extension \(context.envelope.extra["extension_version"]?.stringValue ?? "?"))")
            return BrowserReplies.handshake(version: version)
        }
        table.register(BrowserCommand.importCapture, sources: [.nativeMessaging]) { [app] context in
            if let refusal = await refusal(of: context, app: app) {
                var reply = IPCReply.error(refusal)
                reply.extra["reply_to"] = .string(BrowserCommand.importCapture)
                return reply
            }
            return await importCapture(context, app: app)
        }
        table.register(BrowserCommand.tabChanged, sources: [.nativeMessaging]) { [app] context in
            // No reply, like upstream; a refused report is only logged
            if let refusal = await refusal(of: context, app: app) {
                log.debug("TAB_CHANGED ignored: \(refusal)")
                return nil
            }
            let change = BrowserTabChange(envelope: context.envelope)
            // The address and title stay in memory and out of the log (they are the user's browsing); with the
            // extension's tab tracking turned off the tab is forgotten
            BrowserContext.shared.apply(change, reporter: context.peer?.pid)
            return nil
        }
        // Mac: a stale page must not keep naming captures (the Mac gives `${Browser.*}` to file names)
        app.settings.onChange(of: \.browserExtensionEnabled) { enabled in
            if !enabled { BrowserContext.shared.clear() }
        }
        BrowserIntegration.refreshInstalledManifests()
    }

    /// `IPCServer.Configuration.connectionEnded`: the browser closed the extension's connection (quit, extension turned
    /// off or reloaded), so the tab it reported is forgotten.
    nonisolated static func connectionEnded(_ source: IPCSource, peer: IPCPeer) {
        guard source == .nativeMessaging else { return }
        BrowserContext.shared.clear(reporter: peer.pid)
    }

    /// Nil when the request may run, else why not.
    private nonisolated static func refusal(of context: IPCReplyContext, app: AppDelegate) async -> String? {
        let enabled = await MainActor.run { app.settings.value.browserExtensionEnabled }
        guard enabled else {
            return "[SECURITY] The browser extension is switched off in Settings › Expert › Browser extension."
        }
        guard originGate.isAllowed(context.origin) else {
            log.warn("[SECURITY] Browser extension request rejected: the extension '\(context.origin ?? "")' isn't allowed by the native messaging host manifests.")
            return "[SECURITY] Connection rejected: this extension isn't allowed to connect to Greenshot for Mac."
        }
        return nil
    }

    /// Upstream `HandleImportCaptureAsync`: the image is checked (PNG or JPEG, size from the header) and decoded here,
    /// off the main thread, then handed to the main thread; the extension gets the acknowledgement right away.
    private nonisolated static func importCapture(_ context: IPCReplyContext, app: AppDelegate) async -> IPCReply {
        let request = BrowserImportRequest(envelope: context.envelope, origin: context.origin)
        switch BrowserImportDecoder.decode(base64: request.payload) {
        case .failure(let failure):
            log.warn("IMPORT_CAPTURE rejected: \(failure.message).")
            return BrowserReplies.importRejected(failure.message)
        case .success(let image):
            let width = image.width
            let height = image.height
            let decoded = DecodedImage(image: image)
            await MainActor.run {
                BrowserCaptureImport.deliver(decoded.image, request: request, reporter: context.peer?.pid, app: app)
            }
            log.debug("IMPORT_CAPTURE accepted (\(width)x\(height)).")
            return BrowserReplies.importAccepted(width: width, height: height)
        }
    }
}

/// A decoded image handed to the main thread (CGImage is immutable).
private struct DecodedImage: @unchecked Sendable {
    let image: CGImage
}

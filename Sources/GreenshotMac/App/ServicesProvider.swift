// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Services menu entry "Open in Greenshot for Mac" (Mac only; `NSServices` in Info.plist names the message):
/// image files selected in Finder open in the editor, checked like greenshot-cli's files; an image selected in another
/// app opens as a new screenshot.
@MainActor
final class ServicesProvider: NSObject {
    private weak var app: AppDelegate?
    private let log = Log("Automation")

    init(app: AppDelegate) {
        self.app = app
    }

    @objc func openInGreenshot(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let app else { return }
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty {
            var envelope = IPCEnvelope(command: IPCCommand.openFile)
            envelope.files = files.map(\.path)
            Task { @MainActor in
                let reply = await app.automation.perform(envelope, source: .services)
                if reply.isError {
                    ErrorPresenter.show(message: "The image could not be opened",
                                        detail: AutomationCommands.refusedFileNames(reply, files: envelope.files))
                }
            }
            return
        }
        guard let image = ImagePasteboard.image(from: pasteboard) else {
            error.pointee = "There is no image to open." as NSString
            return
        }
        log.info("Opening an image from the Services menu")
        app.editors.open(Capture(image: image.image, scale: image.scale, title: "Service"))
    }
}

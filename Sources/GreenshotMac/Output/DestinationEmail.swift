// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// A new message in the default mail app with the screenshot attached: port of upstream
/// `Greenshot/Destinations/EmailDestination.cs` (MAPI there, the system's "compose email" sharing service here).
@MainActor
enum EmailDestination {
    /// The running service, kept until it is done.
    private static var service: NSSharingService?

    /// Whether a mail can be written: the compose service or an app for `mailto:` (upstream offers the destination
    /// only with a MAPI client).
    static var isAvailable: Bool {
        if NSSharingService(named: .composeEmail) != nil { return true }
        guard let url = URL(string: "mailto:") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    @discardableResult
    static func send(_ capture: Capture, settings: SettingsStore, saver: ImageSaver) -> ExportResult {
        let mail = settings.value.email
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        let subject = FilenamePattern.fill(mail.subjectPattern, context: context, filenameSafe: false)
        let to = DestinationSupport.recipients(mail.to)
        let cc = DestinationSupport.recipients(mail.cc)
        let bcc = DestinationSupport.recipients(mail.bcc)

        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be attached")
            return .failed(error.localizedDescription)
        }

        // The sharing service attaches the file and knows To and the subject, but not CC and BCC.
        if let compose = NSSharingService(named: .composeEmail), compose.canPerform(withItems: [file]) {
            compose.recipients = to
            compose.subject = subject
            service = compose
            NSApp.activate()
            compose.perform(withItems: [file])
            if !cc.isEmpty || !bcc.isEmpty {
                let missing = [cc.isEmpty ? nil : "CC: " + cc.joined(separator: ", "),
                               bcc.isEmpty ? nil : "BCC: " + bcc.joined(separator: ", ")].compactMap { $0 }
                saver.notify("Add CC and BCC in the mail", detail: missing.joined(separator: "  "), kind: .warning)
            }
            return .succeeded(fileURL: file, clearsModified: false)
        }

        guard let url = DestinationSupport.mailtoURL(to: to, cc: cc, bcc: bcc, subject: subject),
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            ErrorPresenter.show(message: "No mail app is set up",
                                detail: "Set up an account in Mail (or choose a default email app in Mail › Settings), then try again.")
            return .failed("No mail app is set up.")
        }
        NSWorkspace.shared.open(url)
        saver.notify("Drag the screenshot into the new mail",
                     detail: "The mail app can't take attachments from other apps. Click to show the file in Finder.", kind: .warning) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        return .succeeded(fileURL: file, clearsModified: false)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Email")

/// A new message in the default mail app with the screenshot attached: port of upstream
/// `Greenshot/Destinations/EmailDestination.cs` and `MapiMailMessage` (MAPI there). With CC or BCC set and Mail as the
/// mail app, Mail writes it by AppleScript (To, CC, BCC, subject, attachment); otherwise the system's "compose email"
/// sharing service, which knows To and the subject but not CC and BCC, and needs no permission.
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

    /// Whether the default mail app is Apple Mail (which Greenshot can script).
    static var defaultAppIsMail: Bool {
        guard let url = URL(string: "mailto:"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return Bundle(url: app)?.bundleIdentifier?.lowercased() == OfficeApplication.mail.bundleID.lowercased()
    }

    /// The subject: the pattern of the settings (upstream `EmailSubjectPattern`, `${title}`).
    static func subject(for capture: Capture, settings: SettingsStore) -> String {
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        return FilenamePattern.fill(settings.value.email.subjectPattern, context: context, filenameSafe: false)
    }

    static func send(_ capture: Capture, settings: SettingsStore, saver: ImageSaver, completion: @escaping ExportCompletion) {
        let mail = settings.value.email
        let hasCopies = !DestinationSupport.recipients(mail.cc).isEmpty || !DestinationSupport.recipients(mail.bcc).isEmpty
        guard hasCopies, defaultAppIsMail else {
            completion(compose(capture, settings: settings, saver: saver))
            return
        }
        // Mail by AppleScript; when Greenshot isn't allowed to control Mail, the sharing service with the CC/BCC hint.
        Uploads.run("The mail could not be written", progress: "Writing the mail in Mail…", completion: completion) {
            let file = try TemporaryCaptureFile.write(capture, settings: settings)
            let s = settings.value
            do {
                _ = try await AppleScriptRunner.run(OfficeScripts.mailNewMessage(
                    imagePath: file.path, subject: subject(for: capture, settings: settings),
                    to: DestinationSupport.recipients(s.email.to), cc: DestinationSupport.recipients(s.email.cc),
                    bcc: DestinationSupport.recipients(s.email.bcc)))
            } catch let failure as AppleScriptFailure {
                if failure.kind == .cancelled { throw CancellationError() }
                if failure.kind == .notAllowed || failure.kind == .needsConsent {
                    log.info("Not allowed to control Mail: the mail service writes the mail, without CC and BCC")
                    return compose(capture, settings: settings, saver: saver)
                }
                throw OfficeExportError(app: .mail, failure: failure)
            }
            return .succeeded(fileURL: file, target: "Mail", clearsModified: false)
        }
    }

    /// The system's compose service (or `mailto:` without an attachment).
    private static func compose(_ capture: Capture, settings: SettingsStore, saver: ImageSaver) -> ExportResult {
        let mail = settings.value.email
        let subject = subject(for: capture, settings: settings)
        let to = DestinationSupport.recipients(mail.to)
        let cc = DestinationSupport.recipients(mail.cc)
        let bcc = DestinationSupport.recipients(mail.bcc)

        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings)
        } catch {
            log.error("The screenshot could not be attached", error: error)
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

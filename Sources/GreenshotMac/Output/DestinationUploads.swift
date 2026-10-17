// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// What the upload destinations share: the network, the Keychain, the encoded file and how an upload runs.
@MainActor
enum Uploads {
    static let http: HTTPClient = URLSession.shared
    static let secrets: SecretStore = KeychainSecretStore.shared

    /// The file name the pattern gives, with the upload format's extension.
    static func suggestedName(for capture: Capture, settings: SettingsStore, format: UploadFormat) -> String {
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        let name = (FilenamePattern.fileName(settings.value.filenamePattern, context: context) as NSString).lastPathComponent
        return UploadFile.fileName(name, format: format)
    }

    /// The encoded file; `reduceColors` makes it at most 256 colours (upstream `UploadReduceColors`, PNG).
    static func file(_ capture: Capture, name: String, format: UploadFormat, quality: Int, reduceColors: Bool = false) throws -> UploadFile {
        let options = ImageOutputOptions(format: format.imageFormat, jpegQuality: quality, scale: capture.scale,
                                         reduceColors: reduceColors, reduceColorsTo: 256)
        let data = try ImageExporter.data(for: capture.image, options: options)
        return UploadFile(name: UploadFile.fileName(name, format: format), data: data, mimeType: format.mimeType)
    }

    /// Runs the upload and gives its result; shows an error dialog when it fails (nothing when cancelled). A progress
    /// panel with Cancel comes up when it takes longer than 300 ms (upstream `RunWithProgressAsync` with
    /// `communication_wait`).
    static func run(_ failureTitle: String, progress message: String, completion: @escaping ExportCompletion = { _ in },
                    _ operation: @escaping @MainActor () async throws -> ExportResult) {
        let upload = Task { @MainActor in try await operation() }
        let progress = ProgressHolder()
        let delayed = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(UploadProgressPanel.delay * 1_000_000_000))
            let panel = UploadProgressPanel(message: message) { upload.cancel() }
            progress.panel = panel
            panel.show()
        }
        Task { @MainActor in
            let result: ExportResult
            do {
                result = try await upload.value
            } catch {
                delayed.cancel()
                progress.close()
                if isCancellation(error) {
                    completion(.declined)
                } else {
                    ErrorPresenter.show(error, title: failureTitle)
                    completion(.failed(error.localizedDescription))
                }
                return
            }
            delayed.cancel()
            progress.close()
            completion(result)
        }
    }

    /// The progress panel of a running upload, once it is shown.
    @MainActor
    private final class ProgressHolder {
        var panel: UploadProgressPanel?

        func close() {
            panel?.close()
            panel = nil
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let upload = error as? UploadError, upload == .cancelled { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// "X is not set up" with a button to Settings › Destinations.
    static func explainMissingSetup(_ service: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = "\(service) is not set up"
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            (NSApp.delegate as? AppDelegate)?.showSettings(nil)
        }
    }

    static func jiraSite(_ settings: AppSettings) -> AtlassianSite? {
        AtlassianSite(url: settings.jira.url, email: settings.jira.email, apiToken: (try? secrets.secret(for: SecretKey.jiraToken)) ?? "")
    }

    static func confluenceSite(_ settings: AppSettings) -> AtlassianSite? {
        AtlassianSite(url: settings.confluence.url, email: settings.confluence.email, apiToken: (try? secrets.secret(for: SecretKey.confluenceToken)) ?? "")
    }

    static func oauthClient(for destination: CaptureDestination, settings: AppSettings) -> OAuthClient {
        switch destination {
        case .box:
            return OAuthClient(provider: .box, clientID: settings.box.clientID,
                               clientSecret: try? secrets.secret(for: SecretKey.boxClientSecret),
                               store: secrets, storeKey: SecretKey.boxTokens, http: http)
        default:
            return OAuthClient(provider: .dropbox, clientID: settings.dropbox.appKey,
                               store: secrets, storeKey: SecretKey.dropboxTokens, http: http)
        }
    }

    /// Checks the credentials of an Atlassian site: the current user's name, or the error.
    static func testAtlassian(_ site: AtlassianSite, confluence: Bool) async -> Result<String, Error> {
        let request = site.request("GET", path: confluence ? "rest/api/user/current" : "rest/api/3/myself")
        do {
            let object = try HTTPSupport.json(try await HTTPSupport.send(request, with: http))
            return .success(object["displayName"] as? String ?? object["publicName"] as? String ?? object["emailAddress"] as? String ?? "OK")
        } catch {
            return .failure(error)
        }
    }
}

/// "Upload to Jira": port of upstream `Greenshot.Plugin.Jira/Destinations/JiraDestination.cs`. Asks for the issue
/// (a key, a recent issue or a search), attaches the image and adds the comment; with `issueKey` (a picker entry) it
/// attaches right away.
@MainActor
enum JiraDestination {
    static func upload(_ capture: Capture, settings: SettingsStore, saver: ImageSaver, issueKey: String? = nil,
                       completion: @escaping ExportCompletion = { _ in }) {
        let s = settings.value
        guard let site = Uploads.jiraSite(s), !site.email.isEmpty, !site.apiToken.isEmpty else {
            Uploads.explainMissingSetup("Jira", detail: "Enter the Jira URL, your email and an API token in Settings › Destinations.")
            completion(.declined)
            return
        }
        let client = JiraClient(site: site, http: Uploads.http)
        let format = s.jira.uploadFormat
        var key: String
        var filename = Uploads.suggestedName(for: capture, settings: settings, format: format)
        var comment = ""
        if let issueKey {
            key = issueKey
        } else {
            let panel = UploadPickerPanel(JiraPicker.configuration(client: client, settings: s, filename: filename))
            guard let choice = panel.run() else {
                completion(.declined)
                return
            }
            key = choice.row?.id ?? JiraClient.normalizedKey(choice.typedKey)
            filename = choice.filename
            comment = choice.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        key = JiraClient.normalizedKey(key)
        guard JiraClient.isIssueKey(key) else {
            completion(.declined)
            return
        }
        let file: UploadFile
        do {
            file = try Uploads.file(capture, name: filename, format: format, quality: s.jira.jpegQuality, reduceColors: s.jira.reduceColors)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be encoded")
            completion(.failed(error.localizedDescription))
            return
        }
        Uploads.run("The upload to Jira failed", progress: "Transferring data to Jira, please wait…", completion: completion) {
            _ = try await client.attach(file, to: key)
            if !comment.isEmpty { try await client.addComment(comment, to: key) }
            settings.update { $0.jira.remember(issueKey: key) }
            let url = client.browseURL(for: key)
            saver.notify("Attached \(file.name) to \(key)", detail: "Click to open the issue") { NSWorkspace.shared.open(url) }
            return .succeeded(link: url, target: key)
        }
    }
}

/// "Upload to Confluence": port of upstream `Greenshot.Plugin.Confluence/Destinations/ConfluenceDestination.cs`.
/// Finds the page by its title (in one space or all), attaches the image, copies the wiki markup or the image's
/// link, opens the page. With `page` (a picker entry) it attaches right away and doesn't open the page.
@MainActor
enum ConfluenceDestination {
    static func upload(_ capture: Capture, settings: SettingsStore, saver: ImageSaver, page givenPage: ConfluencePage? = nil,
                       completion: @escaping ExportCompletion = { _ in }) {
        let s = settings.value
        guard let site = Uploads.confluenceSite(s), !site.email.isEmpty, !site.apiToken.isEmpty else {
            Uploads.explainMissingSetup("Confluence", detail: "Enter the Confluence URL, your email and an API token in Settings › Destinations.")
            completion(.declined)
            return
        }
        let client = ConfluenceClient(site: site, http: Uploads.http)
        let format = s.confluence.uploadFormat
        var filename = Uploads.suggestedName(for: capture, settings: settings, format: format)
        var comment = ""
        let page: ConfluencePage
        if let givenPage {
            page = givenPage
        } else {
            let picker = ConfluencePicker(client: client, settings: settings, filename: filename)
            guard let choice = picker.run() else {
                completion(.declined)
                return
            }
            page = choice.page
            filename = choice.filename
            comment = choice.comment
        }
        let file: UploadFile
        do {
            file = try Uploads.file(capture, name: filename, format: format, quality: s.confluence.jpegQuality,
                                    reduceColors: s.confluence.reduceColors)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be encoded")
            completion(.failed(error.localizedDescription))
            return
        }
        // Upstream opens the page only after a page was chosen in the dialog.
        let openPage = givenPage == nil && s.confluence.openPageAfterUpload
        Uploads.run("The upload to Confluence failed", progress: "Transferring data to Confluence, please wait…", completion: completion) {
            let attachments = try await client.attach(file, toPage: page.id, comment: comment)
            settings.update { $0.confluence.remember(page: page) }
            var detail = "Click to open the page"
            switch s.confluence.clipboardContent {
            case .nothing: break
            case .wikiMarkup:
                Clipboard.copy(text: ConfluenceClient.wikiMarkup(for: file.name))
                detail = "Wiki markup copied – click to open the page"
            case .imageLink:
                if let link = attachments.first?.downloadURL {
                    Clipboard.copy(text: link.absoluteString)
                    detail = "Image link copied – click to open the page"
                }
            }
            if openPage { NSWorkspace.shared.open(page.url) }
            saver.notify("Attached \(file.name) to “\(page.title)”", detail: detail) { NSWorkspace.shared.open(page.url) }
            return .succeeded(link: attachments.first?.downloadURL ?? page.url, target: page.title)
        }
    }
}

/// "Upload to Box" and "Upload to Dropbox": ports of upstream `BoxDestination.cs` and `DropboxDestination.cs`.
/// Signs in through the browser the first time, uploads, and puts the link on the clipboard.
@MainActor
enum CloudDestination {
    static func upload(_ destination: CaptureDestination, _ capture: Capture, settings: SettingsStore, saver: ImageSaver,
                       completion: @escaping ExportCompletion = { _ in }) {
        let s = settings.value
        let isBox = destination == .box
        let name = isBox ? "Box" : "Dropbox"
        let format = isBox ? s.box.uploadFormat : s.dropbox.uploadFormat
        let quality = isBox ? s.box.jpegQuality : s.dropbox.jpegQuality
        let appKey = isBox ? s.box.clientID : s.dropbox.appKey
        guard !appKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            Uploads.explainMissingSetup(name, detail: "Register your own \(name) app and enter its \(isBox ? "client ID and secret" : "app key") in Settings › Destinations.")
            completion(.declined)
            return
        }
        let file: UploadFile
        do {
            file = try Uploads.file(capture, name: Uploads.suggestedName(for: capture, settings: settings, format: format), format: format, quality: quality)
        } catch {
            ErrorPresenter.show(error, title: "The screenshot could not be encoded")
            completion(.failed(error.localizedDescription))
            return
        }
        let oauth = Uploads.oauthClient(for: destination, settings: s)
        let copyLink = isBox ? s.box.copyLinkToClipboard : s.dropbox.copyLinkToClipboard
        let sharedLink = isBox ? s.box.useSharedLink && copyLink : copyLink
        Uploads.run("The upload to \(name) failed", progress: "Communicating with \(name), please wait…", completion: completion) {
            let result = try await send(file, isBox: isBox, settings: s, oauth: oauth, sharedLink: sharedLink)
            if copyLink { Clipboard.copy(text: result.link.absoluteString) }
            let detail = copyLink ? "Link copied – click to open" : "Click to open"
            saver.notify("Uploaded \(file.name) to \(name)", detail: detail) { NSWorkspace.shared.open(result.link) }
            return .succeeded(link: result.link, target: name)
        }
    }

    /// Uploads with a usable token; a rejected token (401) is dropped and the upload tried once more.
    private static func send(_ file: UploadFile, isBox: Bool, settings: AppSettings, oauth: OAuthClient, sharedLink: Bool) async throws -> CloudUpload {
        for attempt in 0..<2 {
            let token = try await oauth.accessToken(authorizer: BrowserAuthorizer.shared)
            do {
                if isBox {
                    return try await BoxClient(http: Uploads.http).upload(file, folderID: settings.box.folderID, sharedLink: sharedLink, accessToken: token)
                }
                return try await DropboxClient(http: Uploads.http).upload(file, folder: settings.dropbox.folder, sharedLink: sharedLink, accessToken: token)
            } catch UploadError.http(let status, _) where status == 401 && attempt == 0 {
                try oauth.invalidateAccessToken()
            }
        }
        throw UploadError.notSignedIn(isBox ? "Box" : "Dropbox")
    }
}

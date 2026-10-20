// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct NotificationSummaryTests {
    private func exported(_ result: ExportResult, by name: String) -> ExportResult {
        var result = result
        result.exportedBy = name
        return result
    }

    private var all: AppSettings { AppSettings() }

    private func settings(level: NotificationLevel, on: Bool = true) -> AppSettings {
        var settings = AppSettings()
        settings.notificationLevel = level
        settings.showNotifications = on
        return settings
    }

    @Test func oneLinePerExportLikeTheStatusBar() {
        let saved = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/shot.png")
        let exports = [exported(.succeeded(), by: "Copy to clipboard"),
                       exported(.succeeded(fileURL: saved), by: "Save Directly"),
                       exported(.succeeded(link: URL(string: "https://jira.example.com/browse/SHOT-1"), target: "SHOT-1"), by: "Upload to Jira")]
        let content = NotificationSummary.make(title: "Safari – Apple", exports: exports, settings: all)
        let lines = content?.lines ?? []
        #expect(lines.count == 3)
        #expect(lines.first == "Exported to: Copy to clipboard")
        #expect(lines.dropFirst().first == "Image saved to ~/Desktop/shot.png.")
        #expect(lines.last == "Exported to: SHOT-1")
        #expect(content?.title == "Safari – Apple")
        #expect(content?.kind == .info)
        #expect(content?.hasExports == true)
    }

    @Test func declinedAndReasonlessFailuresSayNothing() {
        let exports = [exported(.declined, by: "Save as"), exported(ExportResult(status: .failed), by: "Print")]
        #expect(NotificationSummary.make(title: "x", exports: exports, settings: all) == nil)
        #expect(NotificationSummary.message(for: .declined) == nil)
    }

    @Test func aFailureIsAnErrorRow() {
        let exports = [exported(.succeeded(), by: "Copy to clipboard"),
                       exported(.failed("The server said no."), by: "Upload to Box")]
        let content = NotificationSummary.make(title: "", exports: exports, settings: all)
        #expect(content?.kind == .error)
        #expect(content?.lines.last == "⚠ An error occurred while exporting to Upload to Box: The server said no.")
        #expect(content?.title == "Greenshot")
    }

    @Test func theTargetBeatsTheDestinationName() {
        #expect(NotificationSummary.message(for: exported(.failed("Gone", target: "SHOT-2"), by: "Upload to Jira"))
                == "⚠ An error occurred while exporting to SHOT-2: Gone")
        #expect(NotificationSummary.message(for: .succeeded(), fallbackName: "Print…") == "Exported to: Print")
    }

    @Test func theLevelDecides() {
        let success = [exported(.succeeded(), by: "Copy to clipboard")]
        let failure = success + [exported(.failed("No"), by: "Print")]
        #expect(NotificationSummary.make(title: "x", exports: success, settings: settings(level: .warnings)) == nil)
        #expect(NotificationSummary.make(title: "x", exports: failure, settings: settings(level: .warnings)) != nil)
        #expect(NotificationSummary.make(title: "x", exports: failure, settings: settings(level: .errors)) != nil)
        #expect(NotificationSummary.make(title: "x", exports: failure, settings: settings(level: .none)) == nil)
        #expect(NotificationSummary.make(title: "x", exports: failure, settings: settings(level: .all, on: false)) == nil)
    }

    /// Quick Settings › Show Notifications after Settings said None: on shows notifications again (All, the default).
    @Test func turningNotificationsOnAfterNoneShowsThem() {
        var values = AppSettings()
        values.notificationLevel = .none
        values.showNotifications = false
        #expect(!values.notificationsShown)
        values.setNotificationsShown(true)
        #expect(values.notificationsShown)
        #expect(values.notificationLevel == .all)
        let success = [exported(.succeeded(), by: "Copy to clipboard")]
        #expect(NotificationSummary.shownExports(success, settings: values) == success)
    }

    /// On keeps a level that shows something; off is the picker's None, which also silences warnings and errors.
    @Test func turningNotificationsOffIsNone() {
        var values = settings(level: .warnings, on: false)
        values.setNotificationsShown(true)
        #expect(values.notificationLevel == .warnings && values.showNotifications)
        values.setNotificationsShown(false)
        #expect(values.notificationLevel == .none && !values.showNotifications)
        #expect(!values.notificationsShown)
    }

    @Test func onlyARealSaveIsShownInFinder() {
        let file = URL(fileURLWithPath: "/tmp/shot.png")
        let temporary = URL(fileURLWithPath: "/tmp/mail/shot.png")
        let mail = exported(.succeeded(fileURL: temporary, clearsModified: false), by: "Email")
        #expect(NotificationSummary.savedFile(of: [mail]) == nil)
        let both = [exported(.succeeded(fileURL: file), by: "Save Directly"), mail]
        #expect(NotificationSummary.savedFile(of: both) == file)
        #expect(NotificationSummary.opens(of: both) == file)
        let content = NotificationSummary.make(title: "x", exports: both, settings: all)
        #expect(content?.actions == [.showInFolder])
        #expect(content?.categoryIdentifier == "capture.F")
    }

    @Test func uploadLinksCanBeCopied() {
        let box = URL(string: "https://app.box.com/s/abc")
        let exports = [exported(.succeeded(link: box, target: "Box"), by: "Upload to Box"),
                       exported(.succeeded(link: box, target: "Box"), by: "Upload to Box"),
                       exported(.succeeded(link: URL(string: "file:///etc/passwd")), by: "Odd")]
        let content = NotificationSummary.make(title: "x", exports: exports, settings: all)
        #expect(content?.links == [NotificationLink(text: "Upload to Box: https://app.box.com/s/abc", value: "https://app.box.com/s/abc")])
        #expect(content?.opens?.absoluteString == "file:///etc/passwd")
    }

    @Test func buttonsFollowWhatIsThere() {
        var content = NotificationSummaryContent(kind: .info, title: "x", lines: ["a"])
        #expect(content.actions.isEmpty)
        #expect(content.categoryIdentifier == nil)
        content.captureId = "0190a6e0-0000-7000-8000-000000000000"
        content.links = [NotificationLink(text: "a", value: "https://a.example")]
        #expect(content.actions == [.edit, .copyLink])
        #expect(content.categoryIdentifier == "capture.EL")
        content.savedFile = URL(fileURLWithPath: "/tmp/a.png")
        #expect(content.categoryIdentifier == "capture.EFL")
    }

    @Test func everyButtonCombinationHasACategory() {
        let combinations = NotificationAction.allCombinations
        #expect(combinations.count == 7)
        let identifiers = Set(combinations.compactMap(NotificationAction.categoryIdentifier(for:)))
        #expect(identifiers.count == 7)
        #expect(identifiers.contains("capture.E"))
        #expect(identifiers.contains("capture.FL"))
        #expect(identifiers.contains("capture.EFL"))
    }

    @Test func barcodeRows() {
        let codes = [NotificationBarcode(text: "https://example.com/a?b=c#d", isQRCode: true),
                     NotificationBarcode(text: "https://example.com/a?b=c#d", isQRCode: true),
                     NotificationBarcode(text: "WIFI:S:Home;T:WPA;P:secret;;", isQRCode: true),
                     NotificationBarcode(text: "4006381333931", isQRCode: false),
                     NotificationBarcode(text: "   ", isQRCode: true),
                     NotificationBarcode(text: "one too many", isQRCode: true)]
        let content = NotificationSummary.make(title: "x", exports: [], barcodes: codes, settings: all)
        let lines = content?.lines ?? []
        #expect(lines == ["QR code: https://example.com/a?b=c#d", "QR code: WIFI:S:Home;T:WPA;P:secret;;", "Barcode: 4006381333931"])
        #expect(content?.links == [NotificationLink(text: "QR code: https://example.com/a?b=c#d", value: "https://example.com/a?b=c#d")])
        #expect(content?.hasExports == false)
        #expect(content?.actions == [.copyLink])
    }

    @Test func barcodesAloneOnlyAtTheInfoLevel() {
        let codes = [NotificationBarcode(text: "hello", isQRCode: true)]
        #expect(NotificationSummary.make(title: "x", exports: [], barcodes: codes, settings: settings(level: .warnings)) == nil)
        #expect(NotificationSummary.make(title: "x", exports: [.declined], barcodes: codes, settings: all) != nil)
    }

    @Test func barcodeLinksShowTheHostAsTheDNSSeesIt() {
        // A Cyrillic "а" that looks like a Latin "a".
        let lookalike = NotificationSummary.barcodeDisplay("https://\u{0430}pple.com/login")
        #expect(lookalike.text == "https://xn--pple-43d.com/login")
        #expect(lookalike.link == lookalike.text)
        #expect(NotificationSummary.barcodeDisplay("HTTPS://Example.COM").text == "https://example.com/")
        #expect(NotificationSummary.barcodeDisplay("https://user:pw@example.com/x").text == "https://example.com/x")
        #expect(NotificationSummary.barcodeDisplay("http://example.com:8080/p").text == "http://example.com:8080/p")
        #expect(NotificationSummary.barcodeDisplay("https://example.com:443/p").text == "https://example.com/p")
        #expect(NotificationSummary.barcodeDisplay(" https://example.com/p \n").text == "https://example.com/p")
    }

    @Test func otherBarcodeTextIsShortenedAndNoLink() {
        let script = NotificationSummary.barcodeDisplay("javascript:alert(1)")
        #expect(script.link == nil)
        #expect(script.text == "javascript:alert(1)")
        let long = String(repeating: "a", count: 130)
        let shortened = NotificationSummary.barcodeDisplay(long)
        #expect(shortened.text.count == 121)
        #expect(shortened.text.hasSuffix("…"))
        #expect(NotificationSummary.barcodeDisplay("one\r\ntwo").text == "one  two")
    }

    @Test func webLinksAreHttpOnly() {
        #expect(NotificationSummary.isWebLink("https://example.com"))
        #expect(NotificationSummary.isWebLink("HTTP://example.com/x"))
        #expect(!NotificationSummary.isWebLink("file:///etc/passwd"))
        #expect(!NotificationSummary.isWebLink("javascript:alert(1)"))
        #expect(!NotificationSummary.isWebLink("https://"))
        #expect(!NotificationSummary.isWebLink("greenshot://settings"))
    }

    @Test func detectedQRCodesAreQRCodes() {
        let qr = NotificationBarcode(DetectedBarcode(payload: "a", bounds: .zero, symbology: "QR"))
        let aztec = NotificationBarcode(DetectedBarcode(payload: "a", bounds: .zero, symbology: "Aztec"))
        #expect(qr.isQRCode)
        #expect(!aztec.isQRCode)
    }

    @Test func payloadRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let payload = NotificationPayload(captureId: "0190a6e0-0000-7000-8000-000000000000", savedFile: "/tmp/a.png",
                                          links: [NotificationLink(text: "Box: https://b.example", value: "https://b.example")],
                                          title: "Safari", date: date)
        let info: [AnyHashable: Any] = payload.userInfo.reduce(into: [:]) { $0[$1.key] = $1.value }
        #expect(NotificationPayload(userInfo: info) == payload)
    }

    @Test func payloadIgnoresWrongTypes() {
        let info: [AnyHashable: Any] = ["captureId": 12, "savedFile": ["x"], "links": [["only one"], [1, 2], "x"], "date": "today"]
        let payload = NotificationPayload(userInfo: info)
        #expect(payload == NotificationPayload())
    }

    @Test func savedFileMustStillBeThere() {
        let payload = NotificationPayload(savedFile: "/tmp/a.png")
        #expect(payload.existingSavedFile { _ in true }?.path == "/tmp/a.png")
        #expect(payload.existingSavedFile { _ in false } == nil)
        #expect(NotificationPayload(savedFile: "relative.png").existingSavedFile { _ in true } == nil)
    }
}

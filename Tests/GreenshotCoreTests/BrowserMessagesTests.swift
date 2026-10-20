// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The extension's messages as background.js sends them, read from the envelope, and the app's replies (upstream
/// `IpcSecurityDispatcherTests.SecurityDispatcher_Handshake_ReturnsConfigAndVersion`, `ImportCaptureTests`).
struct BrowserMessagesTests {
    private func envelope(_ json: String) throws -> IPCEnvelope {
        let object = try #require(IPCJSON.parseObject(Data(json.utf8)))
        return IPCEnvelope(json: object)
    }

    @Test func importCaptureIsReadFromTheExtraMembers() throws {
        let message = try envelope("""
            {"source":"native_messaging","command":"IMPORT_CAPTURE","browser":"edge",
             "metadata":{"title":"QA-12: Login","url":"https://jira.example.org/browse/QA-12","timestamp":1700000000,"tab_width":1280},
             "data":{"mime_type":"image/png","encoding":"base64","payload":"iVBORw0KGgo="}}
            """)
        let request = BrowserImportRequest(envelope: message, origin: "chrome-extension://abc/")
        #expect(request.title == "QA-12: Login")
        #expect(request.url == "https://jira.example.org/browse/QA-12")
        #expect(request.browser == "edge")
        #expect(request.tabWidth == 1280)
        #expect(request.payload == "iVBORw0KGgo=")
        #expect(request.metadata == ["url": "https://jira.example.org/browse/QA-12", "browser": "edge"])
    }

    @Test func importCaptureFallbacks() throws {
        let request = BrowserImportRequest(envelope: try envelope(#"{"command":"IMPORT_CAPTURE","metadata":{"title":"  "}}"#),
                                           origin: "companion@greenshot-mac.github.io")
        #expect(request.title == "Browser Capture")
        #expect(request.url.isEmpty)
        #expect(request.payload == nil)
        // Upstream's extension doesn't send "browser" with a capture; a Firefox add-on id as origin says enough
        #expect(request.browser == "firefox")
        #expect(request.metadata == ["browser": "firefox"])
        let chromium = BrowserImportRequest(envelope: try envelope(#"{"command":"IMPORT_CAPTURE"}"#), origin: "chrome-extension://abc/")
        #expect(chromium.browser == nil)
    }

    @Test func browserNamesAreShortLowerCaseWords() {
        #expect(BrowserText.browserName("Chrome", origin: nil) == "chrome")
        #expect(BrowserText.browserName("edge-beta", origin: nil) == "edge-beta")
        #expect(BrowserText.browserName("../etc", origin: nil) == nil)
        #expect(BrowserText.browserName(String(repeating: "a", count: 40), origin: nil) == nil)
        #expect(BrowserText.browserName("", origin: nil) == nil)
    }

    @Test func scaleComesFromTheTabWidth() throws {
        let retina = BrowserImportRequest(envelope: try envelope(#"{"metadata":{"tab_width":1440}}"#))
        #expect(retina.scale(pixelWidth: 2880) == 2)
        #expect(retina.scale(pixelWidth: 1440) == 1)
        // Page zoom makes it uneven: whole numbers only, at most 4
        #expect(retina.scale(pixelWidth: 3200) == 2)
        #expect(retina.scale(pixelWidth: 99_999) == 4)
        let unknown = BrowserImportRequest(envelope: try envelope(#"{"metadata":{"tab_width":0}}"#))
        #expect(unknown.scale(pixelWidth: 2880) == 1)
    }

    @Test func textsLoseControlCharactersAndAreLimited() {
        #expect(BrowserText.clean("a\u{0}b\nc\u{7F}d", limit: 100) == "abcd")
        #expect(BrowserText.clean(String(repeating: "x", count: 3000), limit: BrowserText.urlLimit).count == 2048)
        // A zero-width joiner (format, not control) keeps the family emoji together
        #expect(BrowserText.clean("👩‍💻 Code", limit: 100) == "👩‍💻 Code")
        #expect(BrowserText.clean(" \t ", limit: 100).isEmpty)
    }

    @Test func tabChangeIsReadFromTheExtraMembers() throws {
        let change = BrowserTabChange(envelope: try envelope(#"{"command":"TAB_CHANGED","url":"https://github.com/","title":"GitHub","browser":"chrome"}"#))
        #expect(change.url == "https://github.com/")
        #expect(change.title == "GitHub")
        #expect(change.tracking)
        let off = BrowserTabChange(envelope: try envelope(#"{"command":"TAB_CHANGED","url":"","title":"","tracking":false}"#))
        #expect(!off.tracking)
    }

    @Test func handshakeSaysReadyWithTheVersionAndLeavesTheOptionsToTheExtension() throws {
        let reply = BrowserReplies.handshake(version: "1.2.3").jsonObject
        #expect(reply["status"]?.stringValue == "ready")
        #expect(reply["greenshot_running"]?.boolValue == true)
        #expect(reply["greenshot_version"]?.stringValue == "1.2.3")
        let config = try #require(reply["config"]?.objectValue)
        #expect(config["full_page_delay_ms"]?.doubleValue == 250)
        #expect(config["capture_format"] == nil)
        #expect(config["track_tab_urls"] == nil)
    }

    @Test func importAcknowledgements() {
        let accepted = BrowserReplies.importAccepted(width: 800, height: 600).jsonObject
        #expect(accepted["status"]?.stringValue == "ok")
        #expect(accepted["reply_to"]?.stringValue == "IMPORT_CAPTURE")
        #expect(accepted["exit_code"]?.doubleValue == 0)
        #expect(accepted["width"]?.doubleValue == 800)
        #expect(accepted["height"]?.doubleValue == 600)
        let rejected = BrowserReplies.importRejected("only PNG and JPEG images are accepted").jsonObject
        #expect(rejected["status"]?.stringValue == "error")
        #expect(rejected["reply_to"]?.stringValue == "IMPORT_CAPTURE")
        #expect(rejected["exit_code"]?.doubleValue == 1)
        #expect(rejected["stderr"]?.stringValue == "Error: only PNG and JPEG images are accepted.")
    }
}

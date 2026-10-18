// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// M2 / SL2: what of an external command's output goes into the log.
struct ExternalCommandLogTests {
    @Test func errorsOnlyWhenAskedOrFailed() {
        let quiet = ExternalCommandLog.entries(name: "Up", output: "done", errors: "progress 50%", status: 0, showOutput: false)
        #expect(quiet.isEmpty, "a command that worked, without the option, logs nothing")
        let failed = ExternalCommandLog.entries(name: "Up", output: "done", errors: "no network", status: 6, showOutput: false)
        #expect(failed == [ExternalCommandLog.Entry(level: .warning, message: "Up wrote errors:\nno network")])
        let background = ExternalCommandLog.entries(name: "Up", output: "", errors: "no network", status: nil, showOutput: false)
        #expect(background.isEmpty, "an unknown end counts as not failed")
        let asked = ExternalCommandLog.entries(name: "Up", output: " done \n", errors: "progress", status: 0, showOutput: true)
        #expect(asked == [ExternalCommandLog.Entry(level: .info, message: "Up wrote:\ndone"),
                          ExternalCommandLog.Entry(level: .info, message: "Up wrote errors:\nprogress")])
        let empty = ExternalCommandLog.entries(name: "Up", output: "  ", errors: "\n", status: 1, showOutput: true)
        #expect(empty.isEmpty)
    }

    @Test func credentialsAreReplaced() {
        let curl = "> GET /upload HTTP/1.1\n> Authorization: Bearer abc.def-123\n> authorization:Basic dXNlcjpwYXNz\n< 200 OK"
        let shown = ExternalCommandLog.redacted(curl)
        #expect(shown == "> GET /upload HTTP/1.1\n> Authorization: ***\n> authorization:***\n< 200 OK")
        #expect(ExternalCommandLog.redacted("using bearer eyJhbGciOi.x_y== now") == "using bearer *** now")
        #expect(ExternalCommandLog.redacted("https://x.test/?token=abc123&page=2") == "https://x.test/?token=***&page=2")
        #expect(ExternalCommandLog.redacted("ACCESS_TOKEN=xyz PASSWORD: hunter2") == "ACCESS_TOKEN=*** PASSWORD: ***")
        #expect(ExternalCommandLog.redacted(#"{"apikey": "k-1", "user": "me"}"#) == #"{"apikey": "***", "user": "me"}"#)
        #expect(ExternalCommandLog.redacted("api_key=1 client_secret=2 refresh_token=3") == "api_key=*** client_secret=*** refresh_token=***")
        #expect(ExternalCommandLog.redacted("3 tokens left, password policy ok") == "3 tokens left, password policy ok")
    }

    @Test func longTextIsCut() {
        let long = String(repeating: "e", count: 2_000)
        let shown = ExternalCommandLog.shown(long)
        #expect(shown.count == ExternalCommandLog.maxLength + 1)
        #expect(shown.hasSuffix("…"))
        // Replaced before it is cut: a token at the end of the kept part is never half shown.
        let token = String(repeating: "x", count: 595) + " token=SECRETSECRET"
        #expect(!ExternalCommandLog.shown(token).contains("SECRET"))
        let entries = ExternalCommandLog.entries(name: "Up", output: "", errors: long, status: 1, showOutput: false)
        #expect(entries.first?.message.count == "Up wrote errors:\n".count + ExternalCommandLog.maxLength + 1)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite("OAuth callback")
struct OAuthCallbackTests {
    @Test func anErrorWithoutTheStateIsAStateMismatchNotThePagesText() throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/box?error=server_error&error_description=evil"))
        var message = ""
        do {
            _ = try OAuthFlow.authorizationCode(fromCallback: url, expectedState: "s1")
        } catch UploadError.oauth(let text) {
            message = text
        }
        #expect(!message.isEmpty)
        #expect(!message.contains("evil"))
    }

    @Test func anErrorWithTheStateIsReported() throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/box?error=server_error&error_description=Nope&state=s1"))
        #expect(throws: UploadError.oauth("Nope")) { try OAuthFlow.authorizationCode(fromCallback: url, expectedState: "s1") }
    }

    @Test func theListenerAnswersOnlyTheRedirectWithTheState() throws {
        let page = "/box?error=server_error&error_description=Your%20account%20is%20locked"
        #expect(OAuthFlow.loopbackCallback(requestTarget: page, port: 52398, path: "/box", expectedState: "s1") == nil)
        #expect(OAuthFlow.loopbackCallback(requestTarget: "/box?code=c&state=other", port: 52398, path: "/box", expectedState: "s1") == nil)
        #expect(OAuthFlow.loopbackCallback(requestTarget: "/box", port: 52398, path: "/box", expectedState: "s1") == nil)
        #expect(OAuthFlow.loopbackCallback(requestTarget: "/other?code=c&state=s1", port: 52398, path: "/box", expectedState: "s1") == nil)
        let ok = OAuthFlow.loopbackCallback(requestTarget: "/box?code=c&state=s1", port: 52398, path: "/box", expectedState: "s1")
        #expect(ok?.absoluteString == "http://127.0.0.1:52398/box?code=c&state=s1")
        let denied = OAuthFlow.loopbackCallback(requestTarget: "/box?error=access_denied&state=s1", port: 52398, path: "/box", expectedState: "s1")
        #expect(denied != nil)
    }
}

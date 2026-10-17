// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Where the credentials of Jira and Confluence may go, and which servers the certificate exceptions are for.
struct UploadSecurityTests {
    let site = AtlassianSite(url: "https://jira.example.test", login: .serverPassword, user: "alex", secret: "hunter2")!

    /// The Authorization header of the one request `imageData(at:)` makes for `link`.
    private func authorization(fetching link: String) async throws -> String? {
        let http = StubHTTPClient(body: "PNG")
        _ = try await JiraClient(site: site, http: http).imageData(at: try #require(URL(string: link)))
        return http.last.value(forHTTPHeaderField: "Authorization")
    }

    @Test func iconsOnTheSiteGetTheCredentials() async throws {
        let plain = try await authorization(fetching: "https://jira.example.test/images/icons/bug.png")
        #expect(plain == site.authorizationHeader)
        let upperCase = try await authorization(fetching: "https://JIRA.Example.TEST/images/icons/bug.png")
        #expect(upperCase == site.authorizationHeader)
        let defaultPort = try await authorization(fetching: "https://jira.example.test:443/images/icons/bug.png")
        #expect(defaultPort == site.authorizationHeader)
    }

    @Test func iconsAnywhereElseDoNot() async throws {
        // An http:// icon on the same host would carry the password unencrypted.
        let unencrypted = try await authorization(fetching: "http://jira.example.test/images/icons/bug.png")
        #expect(unencrypted == nil)
        let otherPort = try await authorization(fetching: "https://jira.example.test:8443/images/icons/bug.png")
        #expect(otherPort == nil)
        let otherHost = try await authorization(fetching: "https://avatars.example.test/bug.png")
        #expect(otherHost == nil)
        let lookalike = try await authorization(fetching: "https://jira.example.test.evil.test/bug.png")
        #expect(lookalike == nil)
    }

    @Test func aSiteWithAPortMatchesOnlyThatPort() throws {
        let withPort = try #require(AtlassianSite(url: "http://jira.corp.internal:8080", login: .serverToken, user: "", secret: "t"))
        let samePort = try #require(URL(string: "http://jira.corp.internal:8080/x.png"))
        let noPort = try #require(URL(string: "http://jira.corp.internal/x.png"))
        let otherScheme = try #require(URL(string: "https://jira.corp.internal:8080/x.png"))
        #expect(withPort.isSameOrigin(samePort))
        #expect(!withPort.isSameOrigin(noPort))
        #expect(!withPort.isSameOrigin(otherScheme))
    }
}

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

    // MARK: Secrets bound to their host

    @Test func aTokenIsOnlyForTheHostItWasSavedFor() throws {
        let store = InMemorySecretStore()
        let secrets = AtlassianSecrets(store: store)
        try secrets.setSecret("tok", for: "jira.apiToken", host: "Jira.Example.TEST")
        #expect(try secrets.secret(for: "jira.apiToken", host: "jira.example.test") == "tok")
        // The URL changed to another server: the token stays where it was and isn't given out.
        #expect(try secrets.secret(for: "jira.apiToken", host: "evil.example.test", claim: true) == nil)
        #expect(try secrets.secret(for: "jira.apiToken", host: nil) == nil)
        #expect(try store.secret(for: "jira.apiToken") == "tok")
        // Removing it removes the host too.
        try secrets.setSecret("", for: "jira.apiToken", host: "jira.example.test")
        #expect(store.keys.isEmpty)
    }

    @Test func aTokenOfAnOlderVersionIsBoundAtItsFirstUse() throws {
        let store = InMemorySecretStore(["confluence.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        // The settings show it whatever the URL; only a use binds it.
        #expect(try secrets.secret(for: "confluence.apiToken", host: "wiki.example.test") == "old")
        #expect(try secrets.secret(for: "confluence.apiToken", host: "other.example.test") == "old")
        #expect(try secrets.secret(for: "confluence.apiToken", host: "wiki.example.test", claim: true) == "old")
        #expect(try secrets.secret(for: "confluence.apiToken", host: "other.example.test", claim: true) == nil)
        // Saved before the URL was entered: no host yet, bound like an older one.
        try secrets.setSecret("new", for: "jira.apiToken", host: nil)
        #expect(try store.secret(for: "jira.apiToken.host") == nil)
        #expect(try secrets.secret(for: "jira.apiToken", host: "jira.example.test", claim: true) == "new")
        #expect(try store.secret(for: "jira.apiToken.host") == "jira.example.test")
    }

    @Test func theHostOfASettingsURL() {
        #expect(AtlassianSite.host(ofURL: "Jira.Example.test/") == "jira.example.test")
        #expect(AtlassianSite.host(ofURL: "https://x.atlassian.net/wiki") == "x.atlassian.net")
        #expect(AtlassianSite.host(ofURL: "  ") == nil)
    }

    // MARK: Links and URLs

    @Test func onlyWebPagesOnTheSiteAreOpened() throws {
        let wiki = try #require(AtlassianSite(url: "https://wiki.example.test/wiki", login: .serverToken, user: "", secret: "t"))
        let page = try #require(URL(string: "https://WIKI.example.test/wiki/spaces/DEV/pages/1"))
        let plain = try #require(URL(string: "http://wiki.example.test/display/DEV/x"))
        let file = try #require(URL(string: "file:///Applications/Calculator.app"))
        let otherApp = try #require(URL(string: "x-apple.systempreferences:com.apple.preference.security"))
        let otherHost = try #require(URL(string: "https://evil.example.test/wiki"))
        #expect(wiki.isOnSite(page))
        #expect(wiki.isOnSite(plain))
        #expect(!wiki.isOnSite(file))
        #expect(!wiki.isOnSite(otherApp))
        #expect(!wiki.isOnSite(otherHost))
    }

    @Test func anHttpURLIsUnencrypted() {
        #expect(AtlassianSite.isUnencrypted(url: "http://jira.corp.internal:8080"))
        #expect(AtlassianSite.isUnencrypted(url: "HTTP://jira.corp.internal"))
        #expect(!AtlassianSite.isUnencrypted(url: "jira.corp.internal"))
        #expect(!AtlassianSite.isUnencrypted(url: "https://jira.corp.internal"))
        #expect(!AtlassianSite.isUnencrypted(url: ""))
    }
}

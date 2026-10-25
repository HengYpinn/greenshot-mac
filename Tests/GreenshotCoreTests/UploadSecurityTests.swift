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
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        try secrets.setSecret("tok", for: "jira.apiToken", host: "Jira.Example.TEST")
        let own = try secrets.lookup("jira.apiToken", host: "jira.example.test")
        #expect(own == .bound("tok"))
        // The URL changed to another server: the token stays where it was and isn't given out.
        let other = try secrets.lookup("jira.apiToken", host: "evil.example.test")
        #expect(other == .nothing)
        let noURL = try secrets.lookup("jira.apiToken", host: nil)
        #expect(noURL == .nothing)
        #expect(try secrets.boundSecret(for: "jira.apiToken", host: "evil.example.test") == nil)
        #expect(try secrets.secret(for: "jira.apiToken", host: "evil.example.test") == nil)
        // The host is in the token's own entry, not in a second one.
        #expect(store.keys == ["jira.apiToken"])
        // Removing it removes the host too.
        try secrets.setSecret("", for: "jira.apiToken", host: "jira.example.test")
        #expect(store.keys.isEmpty)
    }

    @Test func aSeparateHostEntryCantGrantAnotherHost() throws {
        // The host comes from the token's own entry: a separate host entry (as older versions kept) for another host,
        // with the URL changed to that host, doesn't give the token there.
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        try secrets.setSecret("tok", for: "jira.apiToken", host: "jira.example.test")
        try store.setSecret("evil.example.test", for: "jira.apiToken.host")
        let elsewhere = try secrets.lookup("jira.apiToken", host: "evil.example.test")
        #expect(elsewhere == .nothing)
        let own = try secrets.lookup("jira.apiToken", host: "jira.example.test")
        #expect(own == .bound("tok"))
    }

    @Test func aTokenOfAnOlderVersionWaitsForTheUsersOK() throws {
        // Saved without its host (older versions kept the host in a second entry): Settings show it, but it goes to
        // no server until the user allows it there.
        let store = RecordingSecretStore(["confluence.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        let wiki = try secrets.lookup("confluence.apiToken", host: "wiki.example.test")
        #expect(wiki == .unbound("old"))
        #expect(try secrets.secret(for: "confluence.apiToken", host: "other.example.test") == "old")
        #expect(try secrets.boundSecret(for: "confluence.apiToken", host: "wiki.example.test") == nil)
        // Reading binds nothing.
        #expect(store.writes.isEmpty)
    }

    @Test func theHostEntryOfAnOlderVersionCanOnlyRefuse() throws {
        // That entry doesn't say where the token belongs, so a matching one doesn't bind it; another host still
        // refuses it, as before.
        let store = RecordingSecretStore(["jira.apiToken": "old", "jira.apiToken.host": "jira.example.test"])
        let secrets = AtlassianSecrets(store: store)
        let matching = try secrets.lookup("jira.apiToken", host: "JIRA.example.test")
        #expect(matching == .unbound("old"))
        let other = try secrets.lookup("jira.apiToken", host: "evil.example.test")
        #expect(other == .nothing)
        #expect(try secrets.secret(for: "jira.apiToken", host: "evil.example.test") == nil)
        #expect(store.writes.isEmpty)
    }

    @Test func theUsersOKBindsItToTheHost() throws {
        let store = RecordingSecretStore(["jira.apiToken": "old", "jira.apiToken.host": "jira.example.test"])
        let secrets = AtlassianSecrets(store: store)
        var asked: [String] = []
        let declined = try secrets.confirmUnbound("jira.apiToken", host: "jira.example.test") {
            asked.append("no")
            return false
        }
        #expect(declined == .declined)
        #expect(store.writes.isEmpty)
        let allowed = try secrets.confirmUnbound("jira.apiToken", host: "Jira.Example.TEST") {
            asked.append("yes")
            return true
        }
        #expect(allowed == .allowed("old"))
        // Kept with its host in one entry; the older second entry is gone.
        #expect(store.keys == ["jira.apiToken"])
        let bound = try secrets.lookup("jira.apiToken", host: "jira.example.test")
        #expect(bound == .bound("old"))
        let other = try secrets.lookup("jira.apiToken", host: "evil.example.test")
        #expect(other == .nothing)
        // Bound now, or for another host: nothing to ask.
        let again = try secrets.confirmUnbound("jira.apiToken", host: "jira.example.test") {
            asked.append("again")
            return true
        }
        #expect(again == .nothingToAsk)
        let elsewhere = try secrets.confirmUnbound("jira.apiToken", host: "evil.example.test") {
            asked.append("evil")
            return true
        }
        #expect(elsewhere == .nothingToAsk)
        #expect(asked == ["no", "yes"])
    }

    @Test func aTokenSavedBeforeTheURLWasEntered() throws {
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        try secrets.setSecret("new", for: "jira.apiToken", host: nil)
        let unbound = try secrets.lookup("jira.apiToken", host: "jira.example.test")
        #expect(unbound == .unbound("new"))
        let allowed = try secrets.confirmUnbound("jira.apiToken", host: "jira.example.test") { true }
        #expect(allowed == .allowed("new"))
        let bound = try secrets.lookup("jira.apiToken", host: "jira.example.test")
        #expect(bound == .bound("new"))
    }

    @Test func aTokenChangedWhileTheUserWasAskedIsLeftAlone() throws {
        let store = RecordingSecretStore(["jira.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        let answer = try secrets.confirmUnbound("jira.apiToken", host: "jira.example.test") {
            try store.setSecret("newer", for: "jira.apiToken")
            return true
        }
        #expect(answer == .declined)
        #expect(try store.secret(for: "jira.apiToken") == "newer")
    }

    @Test func anyTokenSurvivesTheEntry() throws {
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        let marker = AtlassianSecrets.entryMarker
        for token in [marker, marker + "\nhost\nx", "two\nlines", "\r\n", "\nfirst", " spaced "] {
            try secrets.setSecret(token, for: "jira.apiToken", host: "jira.example.test")
            let read = try secrets.lookup("jira.apiToken", host: "jira.example.test")
            #expect(read == .bound(token))
        }
        // An older version's token that only starts like an entry is a token without a host.
        let legacy = RecordingSecretStore(["jira.apiToken": marker + "\nevil.example.test"])
        let looksLikeAnEntry = try AtlassianSecrets(store: legacy).lookup("jira.apiToken", host: "evil.example.test")
        #expect(looksLikeAnEntry == .unbound(marker + "\nevil.example.test"))
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

/// A secret store that notes every write, so a test can tell that a read changed nothing.
private final class RecordingSecretStore: SecretStore, @unchecked Sendable {
    private let base: InMemorySecretStore
    private let lock = NSLock()
    private var written: [String] = []

    init(_ values: [String: String] = [:]) {
        base = InMemorySecretStore(values)
    }

    func secret(for key: String) throws -> String? {
        try base.secret(for: key)
    }

    func setSecret(_ value: String?, for key: String) throws {
        lock.lock()
        written.append(key)
        lock.unlock()
        try base.setSecret(value, for: key)
    }

    /// The keys written, in order.
    var writes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    var keys: [String] { base.keys }
}

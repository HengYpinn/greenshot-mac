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

    // MARK: Secrets bound to their server

    private func server(_ url: String) throws -> AtlassianServer {
        try #require(AtlassianServer(url: url))
    }

    @Test func aTokenIsOnlyForTheServerItWasSavedFor() throws {
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        let jira = try server("https://Jira.Example.TEST")
        try secrets.setSecret("tok", for: "jira.apiToken", server: jira)
        let own = try secrets.lookup("jira.apiToken", server: try server("https://jira.example.test/jira"))
        #expect(own == .bound("tok"))
        // The URL changed to another server: the token stays where it was and isn't given out.
        let evil = try server("https://evil.example.test")
        let other = try secrets.lookup("jira.apiToken", server: evil)
        #expect(other == .nothing)
        let noURL = try secrets.lookup("jira.apiToken", server: nil)
        #expect(noURL == .nothing)
        #expect(try secrets.boundSecret(for: "jira.apiToken", server: evil) == nil)
        #expect(try secrets.secret(for: "jira.apiToken", server: evil) == nil)
        // The server is in the token's own entry, not in a second one.
        #expect(store.keys == ["jira.apiToken"])
        // Removing it removes the server too.
        try secrets.setSecret("", for: "jira.apiToken", server: jira)
        #expect(store.keys.isEmpty)
    }

    @Test func aTokenIsOnlyForTheSchemeAndPortItWasSavedFor() throws {
        let secrets = AtlassianSecrets(store: RecordingSecretStore())
        try secrets.setSecret("tok", for: "jira.apiToken", server: try server("https://jira.example.test"))
        // http:// and another port of the same host are other servers.
        for url in ["http://jira.example.test", "http://jira.example.test:31337/x", "https://jira.example.test:8443"] {
            let elsewhere = try secrets.lookup("jira.apiToken", server: try server(url))
            #expect(elsewhere == .nothing, "\(url)")
        }
        // The scheme's default port, written or not, the case and another path are the same server.
        for url in ["https://jira.example.test:443", "https://JIRA.example.test/other/path", "jira.example.test"] {
            let same = try secrets.lookup("jira.apiToken", server: try server(url))
            #expect(same == .bound("tok"), "\(url)")
        }
        // A server on this computer (the Atlassian SDK's port): another port is another server.
        let local = AtlassianSecrets(store: RecordingSecretStore())
        try local.setSecret("tok", for: "jira.apiToken", server: try server("http://localhost:2990/jira"))
        let otherPort = try local.lookup("jira.apiToken", server: try server("http://localhost:4444"))
        #expect(otherPort == .nothing)
        let samePort = try local.lookup("jira.apiToken", server: try server("http://LOCALHOST:2990/jira/"))
        #expect(samePort == .bound("tok"))
    }

    @Test func settingsAndUploadsFindTheSameServer() throws {
        // Settings keep the token for the server of the URL field; an upload looks it up for its site.
        for url in ["https://Jira.Example.TEST/", "jíra.example.test", "https://JIRA.example.test:8443/jira", "https://[::1]:8443/jira"] {
            let secrets = AtlassianSecrets(store: RecordingSecretStore())
            try secrets.setSecret("tok", for: "jira.apiToken", server: AtlassianServer(url: url))
            let site = try #require(AtlassianSite(url: url, login: .cloudAPIToken, user: "a@example.test", secret: ""))
            let found = try secrets.site(site, key: "jira.apiToken")
            #expect(found.site.secret == "tok", "\(url)")
        }
        let ipv6 = try server("https://[::1]:8443/jira")
        #expect(ipv6.origin == "https://[::1]:8443")
        let idn = try server("jíra.example.test")
        #expect(idn.origin == "https://xn--jra-rma.example.test:443")
    }

    @Test func anUploadGetsOnlyATokenSavedForItsServer() throws {
        // The choice of every upload, recipe step, Test Connection and the destination menu (`AtlassianSignIn.site`).
        let site = try #require(AtlassianSite(url: "https://jira.example.test", login: .cloudAPIToken, user: "a@example.test", secret: ""))
        let legacy = AtlassianSecrets(store: RecordingSecretStore(["jira.apiToken": "old"]))
        let unbound = try legacy.site(site, key: "jira.apiToken")
        #expect(unbound.site.secret.isEmpty)
        #expect(unbound.unbound == "old")
        let bound = AtlassianSecrets(store: RecordingSecretStore())
        try bound.setSecret("tok", for: "jira.apiToken", server: site.server)
        let ready = try bound.site(site, key: "jira.apiToken")
        #expect(ready == AtlassianSecrets.SiteSecret(site: site.with(user: site.user, secret: "tok")))
        let otherPort = try #require(AtlassianSite(url: "https://jira.example.test:8443", login: .cloudAPIToken,
                                                   user: "a@example.test", secret: ""))
        let none = try bound.site(otherPort, key: "jira.apiToken")
        #expect(none == AtlassianSecrets.SiteSecret(site: otherPort))
    }

    @Test func anOlderVersionsHostEntryDoesntOverrideTheEntry() throws {
        // The server comes from the token's own entry; a host entry of an older version doesn't change it.
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        try secrets.setSecret("tok", for: "jira.apiToken", server: try server("https://jira.example.test"))
        try store.setSecret("other.example.test", for: "jira.apiToken.host")
        let other = try secrets.lookup("jira.apiToken", server: try server("https://other.example.test"))
        #expect(other == .nothing)
        let own = try secrets.lookup("jira.apiToken", server: try server("https://jira.example.test"))
        #expect(own == .bound("tok"))
    }

    @Test func aTokenOfAnOlderVersionWaitsForTheUsersOK() throws {
        // Saved without its server (older versions kept the host in a second entry): Settings show it, but it goes to
        // no server until the user allows it there.
        let store = RecordingSecretStore(["confluence.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        let wikiServer = try server("https://wiki.example.test")
        let wiki = try secrets.lookup("confluence.apiToken", server: wikiServer)
        #expect(wiki == .unbound("old"))
        let shown = try secrets.secret(for: "confluence.apiToken", server: try server("https://other.example.test"))
        #expect(shown == "old")
        let sent = try secrets.boundSecret(for: "confluence.apiToken", server: wikiServer)
        #expect(sent == nil)
        // Reading binds nothing.
        #expect(store.writes.isEmpty)
    }

    @Test func theHostEntryOfAnOlderVersionCanOnlyRefuse() throws {
        // That entry doesn't say where the token belongs, so a matching one doesn't bind it; another host still
        // refuses it, as before.
        let store = RecordingSecretStore(["jira.apiToken": "old", "jira.apiToken.host": "jira.example.test"])
        let secrets = AtlassianSecrets(store: store)
        let matching = try secrets.lookup("jira.apiToken", server: try server("https://JIRA.example.test"))
        #expect(matching == .unbound("old"))
        let evil = try server("https://evil.example.test")
        let other = try secrets.lookup("jira.apiToken", server: evil)
        #expect(other == .nothing)
        let shown = try secrets.secret(for: "jira.apiToken", server: evil)
        #expect(shown == nil)
        #expect(store.writes.isEmpty)
    }

    @Test func theUsersOKBindsItToTheServer() throws {
        let store = RecordingSecretStore(["jira.apiToken": "old", "jira.apiToken.host": "jira.example.test"])
        let secrets = AtlassianSecrets(store: store)
        let jira = try server("https://Jira.Example.TEST")
        var asked: [String] = []
        let declined = try secrets.confirmUnbound("jira.apiToken", server: jira) {
            asked.append("no")
            return false
        }
        #expect(declined == .declined)
        #expect(store.writes.isEmpty)
        let allowed = try secrets.confirmUnbound("jira.apiToken", server: jira) {
            asked.append("yes")
            return true
        }
        #expect(allowed == .allowed("old"))
        // Kept with its server in one entry; the older second entry is gone.
        #expect(store.keys == ["jira.apiToken"])
        let bound = try secrets.lookup("jira.apiToken", server: try server("https://jira.example.test"))
        #expect(bound == .bound("old"))
        let otherPort = try secrets.lookup("jira.apiToken", server: try server("https://jira.example.test:8443"))
        #expect(otherPort == .nothing)
        // Bound now, or for another server: nothing to ask.
        let again = try secrets.confirmUnbound("jira.apiToken", server: jira) {
            asked.append("again")
            return true
        }
        #expect(again == .nothingToAsk)
        let elsewhere = try secrets.confirmUnbound("jira.apiToken", server: try server("https://evil.example.test")) {
            asked.append("evil")
            return true
        }
        #expect(elsewhere == .nothingToAsk)
        #expect(asked == ["no", "yes"])
    }

    @Test func aTokenSavedBeforeTheURLWasEntered() throws {
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        let jira = try server("https://jira.example.test")
        try secrets.setSecret("new", for: "jira.apiToken", server: nil)
        let unbound = try secrets.lookup("jira.apiToken", server: jira)
        #expect(unbound == .unbound("new"))
        let allowed = try secrets.confirmUnbound("jira.apiToken", server: jira) { true }
        #expect(allowed == .allowed("new"))
        let bound = try secrets.lookup("jira.apiToken", server: jira)
        #expect(bound == .bound("new"))
    }

    @Test func aTokenWithoutAServerIsNeverGivenOut() throws {
        let secrets = AtlassianSecrets(store: RecordingSecretStore())
        try secrets.setSecret("tok", for: "jira.apiToken", server: nil)
        for url in [nil, "https://jira.example.test"] as [String?] {
            let bound = try secrets.boundSecret(for: "jira.apiToken", server: url.flatMap(AtlassianServer.init(url:)))
            #expect(bound == nil)
        }
    }

    @Test func aTokenChangedWhileTheUserWasAskedIsLeftAlone() throws {
        let store = RecordingSecretStore(["jira.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        let answer = try secrets.confirmUnbound("jira.apiToken", server: try server("https://jira.example.test")) {
            try store.setSecret("newer", for: "jira.apiToken")
            return true
        }
        #expect(answer == .declined)
        #expect(try store.secret(for: "jira.apiToken") == "newer")
        // Another token saved for this server meanwhile (typed in Settings): it stays, and the old one isn't sent.
        let legacy = RecordingSecretStore(["jira.apiToken": "old"])
        let atlassian = AtlassianSecrets(store: legacy)
        let jira = try server("https://jira.example.test")
        let typed = try atlassian.confirmUnbound("jira.apiToken", server: jira) {
            try atlassian.setSecret("newer", for: "jira.apiToken", server: jira)
            return true
        }
        #expect(typed == .declined)
        let kept = try atlassian.lookup("jira.apiToken", server: jira)
        #expect(kept == .bound("newer"))
    }

    @Test func aQuestionAnsweredMeanwhileCountsForTheOtherOne() throws {
        // Two uploads at once: the first Allow keeps the token for the server, and the second Allow still sends it.
        let store = RecordingSecretStore(["jira.apiToken": "old"])
        let secrets = AtlassianSecrets(store: store)
        let jira = try server("https://jira.example.test")
        var inner: AtlassianSecrets.Confirmation?
        let outer = try secrets.confirmUnbound("jira.apiToken", server: jira) {
            inner = try secrets.confirmUnbound("jira.apiToken", server: jira) { true }
            return true
        }
        #expect(inner == .allowed("old"))
        #expect(outer == .allowed("old"))
    }

    @Test func anEntryWithoutASecretIsNothingToAskAbout() throws {
        let entry = try #require(AtlassianSecrets.entry("", origin: nil))
        let secrets = AtlassianSecrets(store: RecordingSecretStore(["jira.apiToken": entry]))
        var asked = 0
        let answer = try secrets.confirmUnbound("jira.apiToken", server: try server("https://jira.example.test")) {
            asked += 1
            return true
        }
        #expect(answer == .nothingToAsk)
        #expect(asked == 0)
    }

    @Test func anyTokenSurvivesTheEntry() throws {
        let store = RecordingSecretStore()
        let secrets = AtlassianSecrets(store: store)
        let jira = try server("https://jira.example.test")
        let marker = AtlassianSecrets.entryMarker
        for token in [marker, marker + "\nhost\nx", "two\nlines", "\r\n", "\nfirst", " spaced "] {
            try secrets.setSecret(token, for: "jira.apiToken", server: jira)
            let read = try secrets.lookup("jira.apiToken", server: jira)
            #expect(read == .bound(token))
        }
        // An older version's token that only starts like an entry is a token without a server, and so is one with
        // line breaks but without the marker.
        let evil = try server("https://evil.example.test")
        let legacy = RecordingSecretStore(["jira.apiToken": marker + "\n" + evil.origin])
        let looksLikeAnEntry = try AtlassianSecrets(store: legacy).lookup("jira.apiToken", server: evil)
        #expect(looksLikeAnEntry == .unbound(marker + "\n" + evil.origin))
        let lines = "a\n" + evil.origin + "\nb"
        let multiline = try AtlassianSecrets(store: RecordingSecretStore(["jira.apiToken": lines])).lookup("jira.apiToken", server: evil)
        #expect(multiline == .unbound(lines))
    }

    @Test func anEntryRefusesAServerWithALineBreak() throws {
        #expect(AtlassianSecrets.entry("tok", origin: "https://jira.example.test:443") != nil)
        #expect(AtlassianSecrets.entry("tok", origin: "https://jira.example.test\nevil.test:443") == nil)
        #expect(AtlassianSecrets.entry("tok", origin: "https://jira.example.test\r:443") == nil)
    }

    @Test func onlyAPlainServerGetsAToken() throws {
        // A user part names another host than it seems to; a percent-encoded line break or non-ASCII letter isn't a
        // plain host name.
        for url in ["https://company.atlassian.net@evil.test", "https://company.atlassian.net%5C@evil.test",
                    "https://company.atlassian.net%2F@evil.test", "https://:pw@jira.example.test", "https://user@jira.example.test",
                    "https://company.atlassian.net%0Aevil.test", "https://company.atla%C3%9Fian.net", "https://[fe80::1%25en0]/",
                    "https://jira.example.test/\u{7}", "https://jira.example.test\u{200E}"] {
            let site = AtlassianSite(url: url, login: .cloudAPIToken, user: "a@example.test", secret: "")
            #expect(site == nil, "\(url)")
            #expect(AtlassianServer(url: url) == nil, "\(url)")
        }
        // Names, international names (as punycode), IP addresses and ports.
        for url in ["https://jira.example.test", "jíra.example.test", "http://localhost:2990/jira", "https://192.168.1.10:8080",
                    "https://[::1]:8443/jira", "https://jira_srv.corp.example", "HTTPS://jira.example.test:65535", "jira.example.test:8443/jira"] {
            let site = AtlassianSite(url: url, login: .cloudAPIToken, user: "a@example.test", secret: "")
            #expect(site != nil, "\(url)")
        }
        let leadingZero = try server("https://jira.example.test:0443")
        #expect(leadingZero.origin == "https://jira.example.test:443")
        // A URL that didn't come through the settings is checked the same way.
        for text in ["https://company.atlassian.net%0Aevil.test", "https://user@jira.example.test", "ftp://jira.example.test"] {
            let raw = try #require(URL(string: text))
            #expect(AtlassianServer(raw) == nil, "\(text)")
        }
    }

    @Test func onlyHttpAndHttpsWithARealPortAndAHostAsItShows() {
        // Other schemes; ports outside 1…65535 (a bigger one would wrap around to another port); a host written with
        // percent signs; one slash after the scheme (the host would be "https").
        for url in ["ftp://jira.example.test", "javascript://jira.example.test", "file://localhost/etc",
                    "https://jira.example.test:0", "https://jira.example.test:65536", "http://127.0.0.1:112547",
                    "https://jira%2Eexample.test", "https://%6Aira.example.test", "https://10.0.0.5%3A8443",
                    "https://%3A%3A1", "https:/jira.example.test", "HTTP:/jira.example.test", "https:jira.example.test"] {
            let site = AtlassianSite(url: url, login: .cloudAPIToken, user: "a@example.test", secret: "")
            #expect(site == nil, "\(url)")
        }
    }

    // MARK: The question before a token kept without its server goes there

    private func unboundSite(_ url: String, login: AtlassianLogin = .cloudAPIToken, user: String = "a@example.test") throws
        -> AtlassianSecrets.SiteSecret {
        let site = try #require(AtlassianSite(url: url, login: login, user: user, secret: ""))
        return AtlassianSecrets.SiteSecret(site: site, unbound: "old")
    }

    @Test func automationIsNeverAskedAndTestConnectionAlwaysIs() throws {
        let answers = AtlassianSecretAnswers()
        let stored = try unboundSite("https://jira.example.test")
        let upload = answers.decide(stored, service: "Jira", request: .upload)
        #expect(upload == .ask("old"))
        let test = answers.decide(stored, service: "Jira", request: .test)
        #expect(test == .ask("old"))
        let automation = answers.decide(stored, service: "Jira", request: .automation)
        #expect(automation == .notAsked)
        // A token saved for the server, a password typed in this session, or none: nothing to ask, whoever asks.
        let bound = AtlassianSecrets.SiteSecret(site: stored.site.with(user: stored.site.user, secret: "tok"))
        let boundByAutomation = answers.decide(bound, service: "Jira", request: .automation)
        #expect(boundByAutomation == .proceed)
        let typed = AtlassianSecrets.SiteSecret(site: stored.site.with(user: stored.site.user, secret: "pw"), unbound: "old")
        let typedUpload = answers.decide(typed, service: "Jira", request: .upload)
        #expect(typedUpload == .proceed)
        let none = AtlassianSecrets.SiteSecret(site: stored.site)
        let noneUpload = answers.decide(none, service: "Jira", request: .upload)
        #expect(noneUpload == .proceed)
    }

    @Test func dontAllowHoldsForUploadsToThatServerThisSession() throws {
        var answers = AtlassianSecretAnswers()
        let jira = try unboundSite("https://jira.example.test")
        let server = try #require(jira.site.server)
        answers.answered(allowed: false, service: "Jira", server: server)
        let upload = answers.decide(jira, service: "Jira", request: .upload)
        #expect(upload == .notAllowed)
        // Test Connection asks again; Confluence and its own answer are apart.
        let test = answers.decide(jira, service: "Jira", request: .test)
        #expect(test == .ask("old"))
        let confluence = answers.decide(jira, service: "Confluence", request: .upload)
        #expect(confluence == .ask("old"))
        // Another server in the URL is asked about; going back to the first one doesn't ask about it again.
        let otherPort = try unboundSite("https://jira.example.test:8443")
        let moved = answers.decide(otherPort, service: "Jira", request: .upload)
        #expect(moved == .ask("old"))
        let otherServer = try #require(otherPort.site.server)
        answers.answered(allowed: false, service: "Jira", server: otherServer)
        let back = answers.decide(jira, service: "Jira", request: .upload)
        #expect(back == .notAllowed)
        let movedAgain = answers.decide(otherPort, service: "Jira", request: .upload)
        #expect(movedAgain == .notAllowed)
        // Allow (at Test Connection) clears it for that server only (and `confirmUnbound` keeps the token for it).
        answers.answered(allowed: true, service: "Jira", server: server)
        let allowed = answers.decide(jira, service: "Jira", request: .upload)
        #expect(allowed == .ask("old"))
        let stillDeclined = answers.decide(otherPort, service: "Jira", request: .upload)
        #expect(stillDeclined == .notAllowed)
    }

    @Test func aTokenThatCantBeUsedYetIsntAskedAbout() throws {
        // A Cloud token without the email, or a password without the user name: not asked about; the setup message or
        // the login dialog asks for what is missing.
        let answers = AtlassianSecretAnswers()
        let noEmail = try unboundSite("https://jira.example.test", user: "")
        let cloud = answers.decide(noEmail, service: "Jira", request: .upload)
        #expect(cloud == .proceed)
        let noUser = try unboundSite("https://jira.example.test", login: .serverPassword, user: " ")
        let password = answers.decide(noUser, service: "Jira", request: .test)
        #expect(password == .proceed)
        // A personal access token needs no user.
        let pat = try unboundSite("https://jira.example.test", login: .serverToken, user: "")
        let token = answers.decide(pat, service: "Jira", request: .upload)
        #expect(token == .ask("old"))
    }

    @Test func aRecipeUploadIsTheUsersOnlyWhenTheUserStartedTheRecipe() {
        for trigger in [WellKnownTriggerType.hotkey, WellKnownTriggerType.manual, WellKnownTriggerType.editor, nil] as [String?] {
            #expect(AtlassianSecretRequest(recipeTrigger: trigger, markedByAutomation: false) == .upload)
        }
        for trigger in [WellKnownTriggerType.aiTool, WellKnownTriggerType.commandline, WellKnownTriggerType.clipboard,
                        WellKnownTriggerType.openFile, WellKnownTriggerType.extension, WellKnownTriggerType.schedule] {
            #expect(AtlassianSecretRequest(recipeTrigger: trigger, markedByAutomation: false) == .automation)
        }
        // A built-in capture that automation started runs as a Manual recipe with the mark.
        #expect(AtlassianSecretRequest(recipeTrigger: WellKnownTriggerType.manual, markedByAutomation: true) == .automation)
        // A destination the user picked (the destination menu, the flyout) is the user's, whoever started the recipe.
        #expect(AtlassianSecretRequest(recipeTrigger: WellKnownTriggerType.extension, markedByAutomation: false,
                                       pickedByUser: true) == .upload)
        #expect(AtlassianSecretRequest(recipeTrigger: WellKnownTriggerType.manual, markedByAutomation: true,
                                       pickedByUser: true) == .upload)
    }

    @Test func aCaptureThatAutomationStartedIsntAsked() {
        // The direct route of a built-in capture (greenshot-cli, a link, AppleScript, Shortcuts) to the destinations.
        #expect(AtlassianSecretRequest(capturedByAutomation: true) == .automation)
        #expect(AtlassianSecretRequest(capturedByAutomation: false) == .upload)
    }

    @Test func theServerOfASettingsURL() throws {
        let jira = try server("Jira.Example.test/")
        #expect(jira.origin == "https://jira.example.test:443")
        let wiki = try server("https://x.atlassian.net/wiki")
        #expect(wiki.origin == "https://x.atlassian.net:443")
        #expect(AtlassianServer(url: "  ") == nil)
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

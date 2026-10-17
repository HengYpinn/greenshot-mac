// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import Testing
@testable import GreenshotCore

/// Upstream `NetworkHelperSecurityTests`: the certificate exceptions for servers of one's own.
struct TLSExceptionsTests {
    /// A self-signed certificate for jira.corp.internal (EC P-256, made with openssl req -x509), as DER.
    static let selfSigned = Data(base64Encoded: "MIICWjCCAf+gAwIBAgIJAPutM8J7Oi+dMAoGCCqGSM49BAMCMB0xGzAZBgNVBAMMEmppcmEuY29ycC5pbnRlcm5hbDAgFw0yNjEwMTcwNTIxMjNaGA8yMTI2MDkyMzA1MjEyM1owHTEbMBkGA1UEAwwSamlyYS5jb3JwLmludGVybmFsMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABGAsnYciZSnY+5Fy8O3pgnWst6l2vkZUri6NrhiAZHsjMyuVaV5Uvi7/6No4P4ol2eeDAHUa8W1NZBn4jl3RutGjMjAwMC4GA1UdEQQnMCWCEmppcmEuY29ycC5pbnRlcm5hbIIJbG9jYWxob3N0hwR/AAABMAoGCCqGSM49BAMCA0kAMEYCIQCw35S7DFCMXGBvvdE35N3ls18mP9BIcziThE7RuAWrPwIhAN82KK2vIVkkK5auwCX3wB+VZXJEF5MoBLIOYbsqrDte")!
    static let sha1 = "B4D4ED03FC9C4A694DF34F8BB2C838F9DC1498A0"
    static let sha256 = "2FD2CC7E80646D896FE6622545621E65B70866677E7C0D635F896FA510E08A33"

    @Test(arguments: [
        ("jira.corp.internal", "jira.corp.internal", true),
        ("JIRA.CORP.INTERNAL", "jira.corp.internal", true),
        ("jira.corp.internal:8443", "jira.corp.internal", true),
        ("jira.corp.internal", "jira.corp.internal:8443", true),
        ("jira.corp.internal", "*.corp.internal", true),
        ("sub.jira.corp.internal", "*.corp.internal", true),
        ("jira.other.internal", "*.corp.internal", false),
        ("api.imgur.com", "jira.corp.internal", false),
        ("", "jira.corp.internal", false),
        ("jira.corp.internal", "", false),
        ("jira1.corp.internal", "jira?.corp.internal", true),
        ("jira12.corp.internal", "jira?.corp.internal", false),
        ("jiraXcorp.internal", "jira.corp.internal", false),
    ])
    func hostPatterns(host: String, pattern: String, expected: Bool) {
        #expect(TLSExceptionPolicy.hostMatches(host, pattern: pattern) == expected)
    }

    @Test func missingHostOrPatternNeverMatches() {
        #expect(!TLSExceptionPolicy.hostMatches(nil, pattern: "jira.corp.internal"))
        #expect(!TLSExceptionPolicy.hostMatches("jira.corp.internal", pattern: nil))
    }

    @Test func dotsInPatternsAreDotsNotWildcards() {
        #expect(!TLSExceptionPolicy.hostMatches("jiraXcorp.internal", pattern: "*.corp.internal"))
        #expect(TLSExceptionPolicy.hostMatches("a.corp.internal", pattern: "*.corp.internal"))
    }

    @Test func fingerprintsOfTheCertificate() {
        let own = TLSExceptionPolicy.fingerprints(of: Self.selfSigned)
        #expect(own.sha1 == Self.sha1)
        #expect(own.sha256 == Self.sha256)
        #expect(TLSExceptionPolicy.displayFingerprint("2fd2cc7e") == "2F:D2:CC:7E")
    }

    @Test func thumbprintsIgnoreColonsSpacesAndCase() {
        #expect(TLSExceptionPolicy.normalizedThumbprint("b4:d4 ed:03") == "B4D4ED03")
        let colons = TLSExceptionPolicy(thumbprints: ["B4:D4:ED:03:FC:9C:4A:69:4D:F3:4F:8B:B2:C8:38:F9:DC:14:98:A0"])
        #expect(colons.acceptsCertificate(Self.selfSigned))
        let lowerSpaced = TLSExceptionPolicy(thumbprints: ["2f d2 cc 7e 80 64 6d 89 6f e6 62 25 45 62 1e 65 b7 08 66 67 7e 7c 0d 63 5f 89 6f a5 10 e0 8a 33"])
        #expect(lowerSpaced.acceptsCertificate(Self.selfSigned))
        let other = TLSExceptionPolicy(thumbprints: ["00:11:22", "   "])
        #expect(!other.acceptsCertificate(Self.selfSigned))
    }

    @Test func decisionsWithoutTheSystem() {
        #expect(!TLSExceptionPolicy().accepts(host: "jira.corp.internal", leafCertificate: Self.selfSigned))
        #expect(TLSExceptionPolicy().isEmpty)
        #expect(TLSExceptionPolicy(hosts: [" "], thumbprints: [""]).isEmpty)
        let servers = ["jira.corp.internal", "other.corp.internal"]
        #expect(TLSExceptionPolicy(hosts: ["jira.corp.internal"], servers: servers).accepts(host: "jira.corp.internal", leafCertificate: nil))
        #expect(!TLSExceptionPolicy(hosts: ["jira.corp.internal"], servers: servers).accepts(host: "other.corp.internal", leafCertificate: Self.selfSigned))
        #expect(TLSExceptionPolicy(thumbprints: [Self.sha1], servers: servers).accepts(host: "other.corp.internal", leafCertificate: Self.selfSigned))
    }

    @Test func settingsFeedThePolicy() {
        var settings = AppSettings()
        settings.allowedUntrustedCertificateHosts = ["*.corp.internal"]
        settings.allowedCertificateThumbprints = [Self.sha256]
        let policy = TLSExceptionPolicy(settings: settings)
        #expect(policy.hosts == ["*.corp.internal"])
        #expect(policy.thumbprints == [Self.sha256])
        #expect(!policy.isEmpty)
    }

    private func trust(for host: String) throws -> SecTrust {
        let certificate = try #require(SecCertificateCreateWithData(nil, Self.selfSigned as CFData))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, host as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func theSystemRejectsTheSelfSignedCertificateAndAnExceptionLetsItThrough() throws {
        let rejected = TLSExceptionPolicy().evaluate(try trust(for: "jira.corp.internal"), host: "jira.corp.internal")
        #expect(rejected == .rejected(fingerprint: Self.sha256))
        let servers = ["jira.corp.internal"]
        let byHost = TLSExceptionPolicy(hosts: ["*.corp.internal"], servers: servers).evaluate(try trust(for: "jira.corp.internal"), host: "jira.corp.internal")
        #expect(byHost == .allowedByException)
        let byPrint = TLSExceptionPolicy(thumbprints: [Self.sha256], servers: servers).evaluate(try trust(for: "jira.corp.internal"), host: "jira.corp.internal")
        #expect(byPrint == .allowedByException)
    }

    @Test func exceptionsAreOnlyForTheJiraAndConfluenceServers() throws {
        var settings = AppSettings()
        settings.allowedUntrustedCertificateHosts = ["*"]
        settings.allowedCertificateThumbprints = [Self.sha256]
        // Without Jira and Confluence URLs no exception counts: the system's check alone.
        let none = TLSExceptionPolicy(settings: settings)
        #expect(none.servers.isEmpty)
        #expect(none.evaluate(try trust(for: "jira.corp.internal"), host: "jira.corp.internal") == .rejected(fingerprint: Self.sha256))
        settings.jira.url = "jira.corp.internal"
        settings.confluence.url = "https://Wiki.Corp.Internal:8443/wiki/"
        let policy = TLSExceptionPolicy(settings: settings)
        #expect(policy.servers == ["jira.corp.internal", "wiki.corp.internal"])
        #expect(policy.evaluate(try trust(for: "jira.corp.internal"), host: "jira.corp.internal") == .allowedByException)
        #expect(policy.accepts(host: "WIKI.corp.internal", leafCertificate: Self.selfSigned))
        // The fingerprint (or "*") vouched for that certificate on any host, Box's and Dropbox's included.
        #expect(policy.evaluate(try trust(for: "api.box.com"), host: "api.box.com") == .rejected(fingerprint: Self.sha256))
        #expect(!policy.accepts(host: "content.dropboxapi.com", leafCertificate: Self.selfSigned))
    }

    @Test func certificateErrorsNameTheFingerprint() {
        let error = UntrustedCertificateError(host: "jira.corp.internal", fingerprint: "2FD2CC7E", underlying: "Not trusted.")
        let text = error.localizedDescription
        #expect(text.contains("2F:D2:CC:7E"))
        #expect(text.contains("Your own servers"))
        #expect(UntrustedCertificateError.isCertificateError(URLError(.serverCertificateUntrusted)))
        #expect(!UntrustedCertificateError.isCertificateError(URLError(.timedOut)))
    }
}

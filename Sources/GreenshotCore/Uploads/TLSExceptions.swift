// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import Security

private let log = Log("TLS")

/// Certificate exceptions for servers of one's own (self-signed or a private CA): port of upstream
/// `Greenshot.Base/Core/NetworkHelper.ValidateServerCertificate` and `IsHostMatch` (581dc36e). They only count after
/// the system's own check failed, and only for the Jira and Confluence servers of the settings (upstream applies them
/// to every connection of the app); empty lists (the default) change nothing.
public struct TLSExceptionPolicy: Equatable, Sendable {
    /// Host names or patterns with `*` and `?` (`AllowedUntrustedCertificateHosts`).
    public var hosts: [String]
    /// SHA-1 or SHA-256 fingerprints of server certificates (`AllowedCertificateThumbprints`).
    public var thumbprints: [String]
    /// The hosts the exceptions are for: those of the Jira and Confluence URLs. Every other server (Box, Dropbox, an
    /// icon elsewhere) gets the system's check alone, so a fingerprint can't vouch for a certificate on another host.
    /// None: no exception counts.
    public var servers: [String]

    public init(hosts: [String] = [], thumbprints: [String] = [], servers: [String] = []) {
        self.hosts = hosts
        self.thumbprints = thumbprints
        self.servers = servers
    }

    public init(settings: AppSettings) {
        self.init(hosts: settings.allowedUntrustedCertificateHosts, thumbprints: settings.allowedCertificateThumbprints,
                  servers: Self.servers(of: settings))
    }

    /// The hosts of the Jira and Confluence URLs of `settings`, read like the uploads read them (`AtlassianSite`).
    public static func servers(of settings: AppSettings) -> [String] {
        [settings.jira.url, settings.confluence.url].compactMap { url in
            AtlassianSite(url: url, login: .serverToken, user: "", secret: "")?.baseURL.host?.lowercased()
        }
    }

    /// Whether `host` is one of `servers` (case doesn't matter).
    public func isServer(_ host: String) -> Bool {
        servers.contains { $0.caseInsensitiveCompare(host) == .orderedSame }
    }

    public var isEmpty: Bool {
        !hosts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            && !thumbprints.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whether a server whose certificate failed the system's check is accepted anyway: only one of `servers`, by the
    /// certificate's fingerprint first, then by the host (upstream's order).
    public func accepts(host: String, leafCertificate der: Data?) -> Bool {
        guard isServer(host) else { return false }
        if let der, acceptsCertificate(der) { return true }
        return acceptsHost(host)
    }

    public func acceptsHost(_ host: String) -> Bool {
        hosts.contains { Self.hostMatches(host, pattern: $0.trimmingCharacters(in: .whitespaces)) }
    }

    public func acceptsCertificate(_ der: Data) -> Bool {
        let own = Self.fingerprints(of: der)
        return thumbprints.contains { allowed in
            let normalized = Self.normalizedThumbprint(allowed)
            return !normalized.isEmpty && (normalized == own.sha1 || normalized == own.sha256)
        }
    }

    /// Upstream `IsHostMatch`: case doesn't matter, a port on either side is ignored, `*` stands for any text and `?`
    /// for one character.
    public static func hostMatches(_ host: String?, pattern: String?) -> Bool {
        guard var host = host?.trimmingCharacters(in: .whitespaces), var pattern = pattern?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !pattern.isEmpty else { return false }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        if let colon = pattern.firstIndex(of: ":") { pattern = String(pattern[..<colon]) }
        if host.caseInsensitiveCompare(pattern) == .orderedSame { return true }
        guard pattern.contains("*") || pattern.contains("?") else { return false }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        return host.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A fingerprint without colons and spaces, upper case (upstream compares them that way).
    public static func normalizedThumbprint(_ text: String) -> String {
        text.filter { $0 != ":" && !$0.isWhitespace }.uppercased()
    }

    /// The SHA-1 (upstream's `X509Certificate2.Thumbprint`) and SHA-256 fingerprints of a certificate, upper-case hex.
    public static func fingerprints(of der: Data) -> (sha1: String, sha256: String) {
        func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
            digest.map { String(format: "%02X", $0) }.joined()
        }
        return (hex(Insecure.SHA1.hash(data: der)), hex(SHA256.hash(data: der)))
    }

    /// "2F:D2:CC:…", the way certificate viewers show a fingerprint.
    public static func displayFingerprint(_ hex: String) -> String {
        let characters = Array(normalizedThumbprint(hex))
        return stride(from: 0, to: characters.count, by: 2).map { String(characters[$0..<min($0 + 2, characters.count)]) }
            .joined(separator: ":")
    }

    /// What became of a server's certificate.
    public enum Decision: Equatable, Sendable {
        /// The system trusts it.
        case trusted
        /// The system doesn't, an exception does.
        case allowedByException
        /// Not trusted; the SHA-256 fingerprint of the server's certificate, when there is one, for the error message.
        case rejected(fingerprint: String?)
    }

    /// The decision for a server trust: the system's check, then the exceptions.
    public func evaluate(_ trust: SecTrust, host: String) -> Decision {
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return .trusted }
        let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first.map { SecCertificateCopyData($0) as Data }
        let reason = error.map { CFErrorCopyDescription($0) as String } ?? ""
        if accepts(host: host, leafCertificate: leaf) {
            log.warn("The certificate of \(host) is accepted by an exception (\(reason))")
            return .allowedByException
        }
        let fingerprint = leaf.map { Self.fingerprints(of: $0).sha256 }
        log.warn("The certificate of \(host) is not trusted (SHA-256 \(fingerprint ?? "unknown")): \(reason)")
        return .rejected(fingerprint: fingerprint)
    }
}

/// The delegate of the upload session: lets a server through whose certificate the exceptions allow. Thread-safe; the
/// app updates the policy from the settings before each upload.
public final class TLSExceptionSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var policy: TLSExceptionPolicy
    private var rejected: [String: String] = [:]

    public init(policy: TLSExceptionPolicy = TLSExceptionPolicy()) {
        self.policy = policy
    }

    public func update(_ policy: TLSExceptionPolicy) {
        lock.lock()
        defer { lock.unlock() }
        self.policy = policy
    }

    /// Whether the exceptions are for `host` (a Jira or Confluence server of the settings), so a certificate error
    /// there can be solved with one.
    public func isServer(_ host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return policy.isServer(host)
    }

    /// The SHA-256 fingerprint of the certificate last rejected for `host`, if any.
    public func rejectedFingerprint(for host: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return rejected[host.lowercased()]
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        lock.lock()
        let current = policy
        lock.unlock()
        let host = challenge.protectionSpace.host
        switch current.evaluate(trust, host: host) {
        case .trusted:
            completionHandler(.performDefaultHandling, nil)
        case .allowedByException:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .rejected(let fingerprint):
            lock.lock()
            rejected[host.lowercased()] = fingerprint
            lock.unlock()
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// A certificate error explained: which server, its fingerprint and where to allow it.
public struct UntrustedCertificateError: Error, LocalizedError, Equatable {
    public var host: String
    /// SHA-256, upper-case hex without separators.
    public var fingerprint: String?
    public var underlying: String

    public init(host: String, fingerprint: String?, underlying: String) {
        self.host = host
        self.fingerprint = fingerprint
        self.underlying = underlying
    }

    /// The server certificate errors of `URLSession` (`NSURLErrorServerCertificate…`).
    public static func isCertificateError(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        switch url.code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        var text = underlying
        if let fingerprint {
            text += "\n\nThe certificate of \(host) has the SHA-256 fingerprint \(TLSExceptionPolicy.displayFingerprint(fingerprint))."
        }
        text += " If this is your own server, add \(host) or the fingerprint under Settings › Destinations › Your own servers."
        return text
    }
}

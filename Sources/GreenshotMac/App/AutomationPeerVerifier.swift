// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import GreenshotCore
import Security

/// The Mac's `IpcClientVerifier`: which program is behind a connection, from the kernel's audit token (no race with a
/// reused process id), where it lives (`IPCPeerPolicy`), and whether its code signature is intact and, when the app is
/// signed with a certificate, made by the same signer.
enum AutomationPeerVerifier {
    private static let log = Log("Automation")

    static func make(hostExecutable: String) -> @Sendable (IPCPeer, IPCSource) -> String? {
        let own = ownSignature()
        let requirementText = IPCPeerPolicy.requirement(teamID: own.teamID, leafCertificateSHA1: own.leafSHA1)
        var compiled: SecRequirement?
        if let requirementText, SecRequirementCreateWithString(requirementText as CFString, [], &compiled) != errSecSuccess {
            log.warn("The code requirement of the app's own signer couldn't be built")
        }
        let requirement = compiled.map(SendableRequirement.init)
        let checksSignature = own.isSigned
        return { peer, source in
            check(peer, source: source, hostExecutable: hostExecutable, checksSignature: checksSignature, requirement: requirement?.value)
        }
    }

    /// SecRequirement is immutable once created.
    private struct SendableRequirement: @unchecked Sendable {
        let value: SecRequirement
    }

    private static func check(_ peer: IPCPeer, source: IPCSource, hostExecutable: String, checksSignature: Bool,
                              requirement: SecRequirement?) -> String? {
        let unknown = "Could not identify the program of the connection."
        guard let token = peer.auditToken else { return unknown }
        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let code = guest,
              let path = executablePath(of: code) else { return unknown }
        if let refusal = IPCPeerPolicy.check(peerExecutable: IPCEndpoint.realPath(path), source: source, hostExecutable: hostExecutable) {
            return refusal
        }
        guard checksSignature else { return nil }
        let status = SecCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else {
            let name = (path as NSString).lastPathComponent
            return "The code signature of \(name) is broken or not the app's (\(status))."
        }
        return nil
    }

    /// The executable of a running program (for an app, the main executable, not the bundle).
    private static func executablePath(of code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        if SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
           let info = information as? [String: Any], let main = info[kSecCodeInfoMainExecutable as String] as? URL {
            return main.path
        }
        var url: CFURL?
        guard SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url else { return nil }
        return (url as URL).path
    }

    /// The app's own signature: signed at all (ad hoc counts: its peers must be intact too), its Team ID, and the SHA-1
    /// of its leaf certificate (a self-signed "Greenshot Dev" has no Team ID).
    private static func ownSignature() -> (isSigned: Bool, teamID: String?, leafSHA1: String?) {
        var me: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticCode) == errSecSuccess, let staticCode else { return (false, nil, nil) }
        guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else { return (false, nil, nil) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any] else { return (true, nil, nil) }
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let leaf = certificates.first.map { certificate -> String in
            let data = SecCertificateCopyData(certificate) as Data
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return (true, teamID, leaf)
    }
}

// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// Who signed a running program (SM-H1): the certificate's name ("Developer ID Application: Anthropic PBC (Q6L2SF6YDW)",
/// "Software Signing" for Apple's programs) and the developer's Team ID. Both nil for an unsigned, ad hoc signed or
/// modified program, and when the process id now belongs to another program.
public struct AIToolSignature: Equatable, Sendable {
    public var signer: String?
    public var teamID: String?

    public init(signer: String? = nil, teamID: String? = nil) {
        self.signer = signer
        self.teamID = teamID
    }

    /// No signature that counts.
    public static let unsigned = AIToolSignature()

    /// The signature of `process` as it runs now (not the file on disk, which may have changed): the running code is
    /// valid by the system's dynamic check (default flags; `kSecCSDoNotValidateResources` isn't one it takes, second
    /// review R2-2), its file is intact apart from its resources (`SecStaticCodeCheckValidity`; checking every resource
    /// of a big app would take seconds), and it is the program the chain walk found (`process.path`).
    public static func running(_ process: AIToolProcess) -> AIToolSignature {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: process.pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let code = guest else { return .unsigned }
        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return .unsigned }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unsigned }
        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil) == errSecSuccess else {
            return .unsigned
        }
        var url: CFURL?
        guard SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url, let path = process.path else { return .unsigned }
        let codePath = IPCEndpoint.realPath((url as URL).path)
        let processPath = IPCEndpoint.realPath(path)
        let bundled = processPath.hasPrefix(codePath.hasSuffix("/") ? codePath : codePath + "/")
        guard codePath == processPath || bundled else { return .unsigned }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first else { return .unsigned }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let summary = SecCertificateCopySubjectSummary(leaf) as String?
        return AIToolSignature(signer: summary.flatMap { $0.isEmpty ? nil : $0 } ?? team, teamID: team)
    }
}

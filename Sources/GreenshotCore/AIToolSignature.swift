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
    /// The app the program belongs to (its outermost `.app`, real path) and that app's signature identifier, when the
    /// app's own signature covers its Info.plist and is the program's or one of the same team (a helper): then the
    /// app's name is its developer's (second review R2-4). Nil otherwise.
    public var appPath: String?
    public var appIdentifier: String?
    /// The names in the Info.plist that app's signature covers (`appInfoKeys`), as the signature has it: the file isn't
    /// read again, so it can't have changed since (third review R3-1).
    public var appInfo: [String: String]?

    public init(signer: String? = nil, teamID: String? = nil, appPath: String? = nil, appIdentifier: String? = nil,
                appInfo: [String: String]? = nil) {
        self.signer = signer
        self.teamID = teamID
        self.appPath = appPath
        self.appIdentifier = appIdentifier
        self.appInfo = appInfo
    }

    /// The Info.plist keys kept in `appInfo`.
    static let appInfoKeys = ["CFBundleDisplayName", "CFBundleName", "CFBundleIdentifier", "CFBundleExecutable"]

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
        var signature = AIToolSignature(signer: summary.flatMap { $0.isEmpty ? nil : $0 } ?? team, teamID: team)
        if let app = outermostApp(processPath) {
            let appInfo = app == codePath ? info : sameTeamSigningInformation(of: app, team: team)
            if let appInfo, let plist = appInfo[kSecCodeInfoPList as String] as? [String: Any] {
                signature.appPath = app
                signature.appIdentifier = appInfo[kSecCodeInfoIdentifier as String] as? String
                signature.appInfo = plist.filter { appInfoKeys.contains($0.key) }.compactMapValues { $0 as? String }
            }
        }
        return signature
    }

    /// The outermost `.app` folder in `path`.
    static func outermostApp(_ path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[...index]))
    }

    /// The signing information of the app at `path` when its file is intact apart from its resources and a developer's
    /// team (`team`, not nil) signed it.
    private static func sameTeamSigningInformation(of path: String, team: String?) -> [String: Any]? {
        guard let team else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], info[kSecCodeInfoTeamIdentifier as String] as? String == team else { return nil }
        return info
    }
}

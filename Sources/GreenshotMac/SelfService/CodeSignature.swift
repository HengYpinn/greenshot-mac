// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore
import Security

/// What the code signature of the app says: the Mac's version of upstream's check of the installed files against
/// `checksum.SHA256` (`ChecksumSectionViewModel.cs`). A changed or damaged file breaks the signature.
struct SignatureReport: Equatable {
    enum Notarization: Equatable { case checking, notarized, notNotarized, notApplicable }

    var location: String
    var isAppBundle: Bool
    /// The signature is intact (nil: couldn't check).
    var valid: Bool?
    var validity: String
    var signer: String
    var identifier: String?
    var teamID: String?
    var hardenedRuntime: Bool
    var cdHash: String?
    var notarization: Notarization
    var quarantined: Bool
    var translocated: Bool

    /// Problems worth a badge: a broken signature, a translocated copy.
    var problemCount: Int {
        (valid == false ? 1 : 0) + (translocated ? 1 : 0)
    }

    var reportText: String {
        var lines = ["=== \(AppInfo.name) Integrity ===",
                     "Location: \(location)",
                     "Signature: \(validity)",
                     "Signed by: \(signer)"]
        if let identifier { lines.append("Identifier: \(identifier)") }
        if let teamID { lines.append("Team: \(teamID)") }
        lines.append("Hardened runtime: \(hardenedRuntime ? "yes" : "no")")
        if let cdHash { lines.append("Code directory hash: \(cdHash)") }
        lines.append("Notarized: \(notarizationText)")
        lines.append("Quarantined (downloaded, not opened yet): \(quarantined ? "yes" : "no")")
        lines.append("Run from a translocated copy: \(translocated ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    var notarizationText: String {
        switch notarization {
        case .checking: return "checking…"
        case .notarized: return "yes, Apple checked this build"
        case .notNotarized: return "no"
        case .notApplicable: return "not applicable (not signed with a Developer ID)"
        }
    }
}

enum CodeSignature {
    /// The app bundle, or the bare executable of a `swift build`.
    static var codeURL: URL {
        Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : (Bundle.main.executableURL ?? Bundle.main.bundleURL)
    }

    static func check(_ url: URL = codeURL) -> SignatureReport {
        let location = DiagnosticReport.abbreviatingHome(url.path)
        var report = SignatureReport(location: location, isAppBundle: url.pathExtension == "app", valid: nil,
                                     validity: "Could not be checked", signer: "Unknown", identifier: nil, teamID: nil,
                                     hardenedRuntime: false, cdHash: nil, notarization: .notApplicable,
                                     quarantined: isQuarantined(url), translocated: url.path.contains("/AppTranslocation/"))
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return report }

        var errors: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSCheckNestedCode) | UInt32(kSecCSStrictValidate))
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &errors)
        switch status {
        case errSecSuccess:
            report.valid = true
            report.validity = "Valid: no file of the app was changed"
        case errSecCSUnsigned:
            report.valid = nil
            report.validity = "Not signed"
        default:
            report.valid = false
            let message = errors?.takeRetainedValue().localizedDescription ?? (SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")
            report.validity = "Broken: \(message)"
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &information) == errSecSuccess,
              let info = information as? [String: Any] else { return report }
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        report.identifier = info[kSecCodeInfoIdentifier as String] as? String
        report.teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        report.hardenedRuntime = codeFlags & 0x10000 != 0
        report.cdHash = (info[kSecCodeInfoUnique as String] as? Data).map { $0.map { String(format: "%02x", $0) }.joined() }
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        if let leaf = certificates.first, let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            report.signer = summary
            report.notarization = report.teamID == nil ? .notApplicable : .checking
        } else if codeFlags & 0x20000 != 0 {
            report.signer = "Signed by the linker (a development build)"
        } else if codeFlags & 0x2 != 0 {
            report.signer = "Ad-hoc (no certificate: a local build)"
        } else if status == errSecCSUnsigned {
            report.signer = "Nobody"
        }
        return report
    }

    /// Whether Apple notarized this build (the requirement "notarized"; may look online, so off the main thread).
    static func isNotarized(_ url: URL = codeURL) -> Bool {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode,
              SecRequirementCreateWithString("notarized" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func isQuarantined(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.quarantinePropertiesKey]))?.quarantineProperties != nil
    }
}

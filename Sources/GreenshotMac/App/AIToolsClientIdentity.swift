// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import GreenshotCore
import Security

/// Which AI tool is behind a greenshot-mcp connection (upstream `AiToolCaller.TryIdentify`): greenshot-mcp's process
/// from the connection's audit token, the program that started it (`AIToolCaller`), and that program's signer. Cached per
/// greenshot-mcp process: the walk and the signature check run once per session.
@MainActor
final class AIToolsClientIdentity {
    private var clients: [String: AIToolClient] = [:]
    private var signers: [String: String?] = [:]
    private let table = SystemProcessTable()
    private let log = Log("AITools")

    /// The AI tool of the request; else why it can't be identified.
    func client(of context: IPCReplyContext) -> Result<AIToolClient, AIToolError> {
        guard context.source == .mcp, let peer = context.peer else { return .failure(AIToolError(AIToolAccess.unidentifiedMessage)) }
        let pid = Self.processID(of: peer)
        guard let server = table.process(pid) else { return .failure(AIToolError(AIToolAccess.unidentifiedMessage)) }
        let key = "\(server.pid):\(server.startTime)"
        if let known = clients[key] { return .success(known) }
        let result = AIToolCaller.identify(serverPID: pid, table: table) { [self] path in signer(of: path) }
        switch result {
        case .success(let client):
            clients[key] = client
            log.info("greenshot-mcp (\(pid)) was started by \(client.logText), \(client.signer.map { "signed by \($0)" } ?? "not signed")")
        case .failure(let error):
            log.warn("[SECURITY] greenshot-mcp (\(pid)): \(error.message)")
        }
        return result
    }

    /// The process id in the audit token (race-free), else the one of `LOCAL_PEERPID`.
    static func processID(of peer: IPCPeer) -> pid_t {
        guard let token = peer.auditToken, token.count == MemoryLayout<audit_token_t>.size else { return peer.pid }
        let audit = token.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
        return pid_t(bitPattern: audit.val.5)
    }

    /// The certificate holder of a valid developer signature ("Developer ID Application: Anthropic PBC (Q6L2SF6YDW)"),
    /// nil for an unsigned, ad hoc signed or broken program. Only the signature itself is checked (not every file of a
    /// big app): enough to name the signer; cached per path and modification date.
    func signer(of path: String) -> String? {
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(path)|\(date)"
        if let known = signers[key] { return known }
        let value = Self.readSigner(path)
        signers[key] = value
        return value
    }

    private static func readSigner(_ path: String) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        let basic = SecCSFlags(rawValue: kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources)
        guard SecStaticCodeCheckValidity(staticCode, basic, nil) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first else { return nil }
        let summary = SecCertificateCopySubjectSummary(leaf) as String?
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        guard let summary, !summary.isEmpty else { return team }
        return summary
    }
}

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
/// greenshot-mcp process and its ancestors: the walk and the signature check run once per session.
@MainActor
final class AIToolsClientIdentity {
    private var clients: [String: AIToolClient] = [:]
    private let table = SystemProcessTable()
    private let log = Log("AITools")

    /// The AI tool of the request; else why it can't be identified or may not ask (`AIToolCaller.identity`).
    func client(of context: IPCReplyContext) -> Result<AIToolClient, AIToolError> {
        guard context.source == .mcp, let peer = context.peer else { return .failure(AIToolError(AIToolAccess.unidentifiedMessage)) }
        let pid = Self.processID(of: peer)
        guard let server = table.process(pid) else { return .failure(AIToolError(AIToolAccess.unidentifiedMessage)) }
        // The ancestors the walk can reach are part of the key: one that exec'd another program after starting greenshot-mcp
        // (exec swap) or went away must not keep the identity it had when it was identified (security review M1)
        var key = Self.cacheKey(server)
        var next = server
        for _ in 0...AIToolCaller.maximumLauncherDepth {
            guard next.parentPID > 1, let ancestor = table.process(next.parentPID) else { break }
            key += "/" + Self.cacheKey(ancestor)
            next = ancestor
        }
        if let known = clients[key] { return .success(known) }
        let result = AIToolCaller.identify(serverPID: pid, table: table) { Self.runningSigner($0) }
        switch result {
        case .success(let client):
            clients[key] = client
            log.info("greenshot-mcp (\(pid)) was started by \(client.logText), \(client.signer.map { "signed by \($0)" } ?? "not signed by a developer")")
        case .failure(let error):
            log.warn("[SECURITY] greenshot-mcp (\(pid)): \(error.message)")
        }
        return result
    }

    nonisolated private static func cacheKey(_ process: AIToolProcess) -> String {
        "\(process.pid):\(process.startTime):\(process.uniqueID ?? 0):\(process.idVersion ?? 0)"
    }

    /// The process id in the audit token (race-free), else the one of `LOCAL_PEERPID`.
    static func processID(of peer: IPCPeer) -> pid_t {
        guard let token = peer.auditToken, token.count == MemoryLayout<audit_token_t>.size else { return peer.pid }
        let audit = token.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
        return pid_t(bitPattern: audit.val.5)
    }

    /// Who signed the running program (SM-H1): its code as it runs now (not the file on disk, which may have changed),
    /// checked to be intact; the certificate's name ("Developer ID Application: Anthropic PBC (Q6L2SF6YDW)") and the
    /// Team ID. Nil for an unsigned, ad hoc signed or modified program, and when the process id now belongs to another
    /// program. All its resources aren't checked: enough to name the signer of a big app without seconds of hashing.
    nonisolated static func runningSigner(_ process: AIToolProcess) -> (name: String?, teamID: String?) {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: process.pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let code = guest else { return (nil, nil) }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        guard SecCodeCheckValidity(code, flags, nil) == errSecSuccess else { return (nil, nil) }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return (nil, nil) }
        // The same program the chain walk found
        var url: CFURL?
        if SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url, let path = process.path {
            let codePath = IPCEndpoint.realPath((url as URL).path)
            let processPath = IPCEndpoint.realPath(path)
            let bundled = processPath.hasPrefix(codePath.hasSuffix("/") ? codePath : codePath + "/")
            guard codePath == processPath || bundled else { return (nil, nil) }
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first else { return (nil, nil) }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let summary = SecCertificateCopySubjectSummary(leaf) as String?
        return (summary.flatMap { $0.isEmpty ? nil : $0 } ?? team, team)
    }
}

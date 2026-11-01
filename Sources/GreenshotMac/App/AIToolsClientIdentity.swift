// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import GreenshotCore

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
        let result = AIToolCaller.identify(serverPID: pid, table: table) { AIToolSignature.running($0) }
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
}

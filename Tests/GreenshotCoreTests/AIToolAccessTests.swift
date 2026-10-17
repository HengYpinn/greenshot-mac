// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream AiToolAccessTests: opt-in, consent per program, the identification of the program behind greenshot-mcp.
@Suite struct AIToolAccessTests {
    private func settings(enabled: Bool = true, proposals: Bool = true, allowed: [String] = []) -> AIToolsSettings {
        var settings = AIToolsSettings()
        settings.enabled = enabled
        settings.allowRecipeProposals = proposals
        settings.allowedClients = allowed
        return settings
    }

    @Test func defaults() {
        let defaults = AIToolsSettings()
        #expect(defaults.enabled == false)
        #expect(defaults.allowRecipeProposals)
        #expect(defaults.notifyOnCapture)
        #expect(defaults.allowedClients.isEmpty)
        #expect(defaults.excludedApplications.contains("1Password"))
        #expect(defaults.excludedApplications.contains("Keychain Access"))
    }

    @Test func switchedOffOnlyTheVersionAnswers() {
        let off = settings(enabled: false)
        #expect(AIToolAccess.optInRefusal(command: "VERSION", source: .mcp, settings: off) == nil)
        for command in IPCCommand.aiToolCommands {
            #expect(AIToolAccess.optInRefusal(command: command, source: .mcp, settings: off) == AIToolAccess.disabledMessage)
        }
        // Other sources aren't AI tools
        #expect(AIToolAccess.optInRefusal(command: "SETTINGS", source: .cli, settings: off) == nil)
    }

    @Test func proposalsHaveTheirOwnSwitch() {
        let noProposals = settings(proposals: false)
        #expect(AIToolAccess.optInRefusal(command: "PROPOSE_RECIPE", source: .mcp, settings: noProposals) == AIToolAccess.proposalsDisabledMessage)
        #expect(AIToolAccess.optInRefusal(command: "VALIDATE_RECIPE", source: .mcp, settings: noProposals) == nil)
    }

    @Test func consentFor() {
        #expect(!AIToolAccess.requiresConsent(command: "VERSION", source: .mcp))
        #expect(!AIToolAccess.requiresConsent(command: "list_ai_tools", source: .mcp))
        #expect(AIToolAccess.requiresConsent(command: "LIST_WINDOWS", source: .mcp))
        #expect(AIToolAccess.requiresConsent(command: "RECIPE_CATALOG", source: .mcp))
        #expect(!AIToolAccess.requiresConsent(command: "SETTINGS", source: .cli))
    }

    @Test func allowedByPathWhateverTheCase() {
        let client = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude")
        #expect(AIToolAccess.isAllowed(client, settings: settings(allowed: ["/applications/claude.app/contents/macos/claude "])))
        #expect(!AIToolAccess.isAllowed(client, settings: settings(allowed: ["/Applications/Cursor.app/Contents/MacOS/Cursor"])))
        #expect(!AIToolAccess.isAllowed(AIToolClient(path: "", displayName: "?"), settings: settings(allowed: [""])))
    }

    @Test func captureNotice() {
        #expect(AIToolAccess.captureNotice(client: "Claude", what: "'Mail' (Capture window)") == "Claude captured 'Mail' (Capture window) with Greenshot.")
        #expect(AIToolAccess.captureNotice(client: " ", what: "the screen").hasPrefix("An AI tool captured"))
    }

    @Test func scopeKeyIsTheSessionAndTheProgram() {
        let one = AIToolClient(path: "/A", displayName: "A", serverProcessID: 10, serverStartTime: 5)
        let other = AIToolClient(path: "/A", displayName: "A", serverProcessID: 11, serverStartTime: 5)
        #expect(one.scopeKey != other.scopeKey)
    }
}

/// The user's answers in one run of the app.
@MainActor
@Suite struct AIToolConsentTests {
    private let client = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude")

    @Test func asksOnceAndRemembersTheAnswer() async {
        let consent = AIToolConsent()
        var stored = AIToolsSettings()
        var asked = 0
        let allowed = await consent.ensureAllowed(client, settings: { stored }, managed: false,
                                                  prompt: { _ in asked += 1; return true },
                                                  allow: { stored.allowedClients.append($0) })
        #expect(allowed)
        #expect(stored.allowedClients == [client.path])
        let again = await consent.ensureAllowed(client, settings: { stored }, managed: false,
                                                prompt: { _ in asked += 1; return false }, allow: { _ in })
        #expect(again)
        #expect(asked == 1)
    }

    @Test func dontAllowLastsUntilAskAgain() async {
        let consent = AIToolConsent()
        var asked = 0
        let first = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                prompt: { _ in asked += 1; return false }, allow: { _ in })
        let second = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                 prompt: { _ in asked += 1; return true }, allow: { _ in })
        #expect(!first)
        #expect(!second)
        #expect(asked == 1)
        #expect(consent.deniedClients == [client.path])
        consent.forgetDenied(client.path)
        let third = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                prompt: { _ in asked += 1; return true }, allow: { _ in })
        #expect(third)
        #expect(asked == 2)
    }

    @Test func managedListAsksNobody() async {
        let consent = AIToolConsent()
        var asked = false
        let allowed = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: true,
                                                  prompt: { _ in asked = true; return true }, allow: { _ in })
        #expect(!allowed)
        #expect(!asked)
    }

    @Test func unidentifiedIsNeverAllowed() async {
        let consent = AIToolConsent()
        let allowed = await consent.ensureAllowed(nil, settings: { AIToolsSettings() }, managed: false, prompt: { _ in true }, allow: { _ in })
        #expect(!allowed)
    }

    @Test func oneQuestionAtATime() async {
        let consent = AIToolConsent()
        let box = ConsentBox()
        let client = client
        // The first question waits for the second request to arrive; the second sees the first answer and isn't asked.
        async let first = consent.ensureAllowed(client, settings: { box.settings }, managed: false,
                                                prompt: { _ in
                                                    box.asked += 1
                                                    await Task.yield()
                                                    await Task.yield()
                                                    return true
                                                },
                                                allow: { box.settings.allowedClients.append($0) })
        async let second = consent.ensureAllowed(client, settings: { box.settings }, managed: false,
                                                 prompt: { _ in box.asked += 1; return true },
                                                 allow: { box.settings.allowedClients.append($0) })
        let answers = await [first, second]
        #expect(answers == [true, true])
        #expect(box.asked == 1)
        #expect(box.settings.allowedClients.count == 1)
    }
}

@MainActor
final class ConsentBox {
    var asked = 0
    var settings = AIToolsSettings()
}

/// A process table for the tests.
struct FakeProcessTable: AIToolProcessTable {
    var processes: [Int32: AIToolProcess]

    init(_ list: [AIToolProcess]) {
        processes = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
    }

    func process(_ pid: Int32) -> AIToolProcess? { processes[pid] }
}

/// Upstream AiToolCaller: the program that started greenshot-mcp, shells skipped.
@Suite struct AIToolCallerTests {
    private let server = AIToolProcess(pid: 500, parentPID: 400, startTime: 1000, path: "/Applications/G.app/Contents/Helpers/greenshot-mcp")

    @Test func skipsShells() throws {
        let table = FakeProcessTable([server,
                                      AIToolProcess(pid: 400, parentPID: 300, startTime: 900, path: "/bin/zsh"),
                                      AIToolProcess(pid: 300, parentPID: 200, startTime: 800, path: "/usr/bin/env"),
                                      AIToolProcess(pid: 200, parentPID: 1, startTime: 700, path: "/opt/homebrew/bin/node")])
        let client = try AIToolCaller.identify(serverPID: 500, table: table, signer: { _ in "Dev" }).get()
        #expect(client.path == "/opt/homebrew/bin/node")
        #expect(client.displayName == "node")
        #expect(client.signer == "Dev")
        #expect(client.serverProcessID == 500)
        #expect(client.serverStartTime == 1000)
    }

    @Test func refusesReusedAndOrphanedProcesses() {
        let reused = FakeProcessTable([server, AIToolProcess(pid: 400, parentPID: 1, startTime: 2000, path: "/Applications/X.app/Contents/MacOS/X")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: reused, signer: { _ in nil }).get()) == nil)
        let orphan = FakeProcessTable([AIToolProcess(pid: 500, parentPID: 1, startTime: 1000, path: "/x/greenshot-mcp")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: orphan, signer: { _ in nil }).get()) == nil)
        let onlyShells = FakeProcessTable([server, AIToolProcess(pid: 400, parentPID: 1, startTime: 900, path: "/bin/sh")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: onlyShells, signer: { _ in nil }).get()) == nil)
    }

    @Test func stopsAfterFiveLaunchers() {
        var list = [server]
        for index in 0..<7 {
            let pid = Int32(400 - index)
            list.append(AIToolProcess(pid: pid, parentPID: pid - 1, startTime: UInt64(900 - index), path: "/bin/bash"))
        }
        list.append(AIToolProcess(pid: 393, parentPID: 1, startTime: 10, path: "/Applications/Tool.app/Contents/MacOS/Tool"))
        #expect((try? AIToolCaller.identify(serverPID: 500, table: FakeProcessTable(list), signer: { _ in nil }).get()) == nil)
    }

    @Test func names() {
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Claude.app/Contents/MacOS/Claude") == "Claude")
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Claude.app/Contents/Helpers/disclaimer") == "Claude (disclaimer)")
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper")
                == "Cursor (Cursor Helper)")
        #expect(AIToolCaller.displayName(forExecutable: "/Users/me/.local/share/claude/versions/2.1.0") == "claude (2.1.0)")
        #expect(AIToolCaller.displayName(forExecutable: "/usr/local/bin/codex") == "codex")
    }

    @Test func realTableKnowsThisProcess() throws {
        let me = try #require(SystemProcessTable().process(getpid()))
        #expect(me.pid == getpid())
        #expect(me.path != nil)
        #expect(me.startTime > 0)
    }
}

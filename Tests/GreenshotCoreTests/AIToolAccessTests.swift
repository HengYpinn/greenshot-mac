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
    private let client = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude", teamID: "Q6L2SF6YDW")

    @Test func asksOnceAndRemembersTheAnswer() async {
        let consent = AIToolConsent()
        var stored = AIToolsSettings()
        var asked = 0
        let refusal = await consent.ensureAllowed(client, settings: { stored }, managed: false,
                                                  prompt: { _ in asked += 1; return true },
                                                  allow: { stored.allowedClients = AIToolAccess.allowing($0, in: stored.allowedClients) })
        #expect(refusal == nil)
        #expect(stored.allowedClients == ["/Applications/Claude.app/Contents/MacOS/Claude | Team ID: Q6L2SF6YDW"])
        let again = await consent.ensureAllowed(client, settings: { stored }, managed: false,
                                                prompt: { _ in asked += 1; return false }, allow: { _ in })
        #expect(again == nil)
        #expect(asked == 1)
    }

    @Test func dontAllowLastsUntilAskAgain() async {
        let consent = AIToolConsent()
        var asked = 0
        let first = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                prompt: { _ in asked += 1; return false }, allow: { _ in })
        let second = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                 prompt: { _ in asked += 1; return true }, allow: { _ in })
        #expect(first == AIToolAccess.notAllowedMessage)
        #expect(second == AIToolAccess.notAllowedMessage)
        #expect(asked == 1)
        #expect(consent.deniedClients.map(\.key) == [client.key])
        consent.forgetDenied(client.key)
        let third = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: false,
                                                prompt: { _ in asked += 1; return true }, allow: { _ in })
        #expect(third == nil)
        #expect(asked == 2)
    }

    @Test func managedListAsksNobody() async {
        let consent = AIToolConsent()
        var asked = false
        let refusal = await consent.ensureAllowed(client, settings: { AIToolsSettings() }, managed: true,
                                                  prompt: { _ in asked = true; return true }, allow: { _ in })
        #expect(refusal == AIToolAccess.managedMessage)
        #expect(!asked)
    }

    @Test func unidentifiedIsNeverAllowed() async {
        let consent = AIToolConsent()
        let refusal = await consent.ensureAllowed(nil, settings: { AIToolsSettings() }, managed: false, prompt: { _ in true }, allow: { _ in })
        #expect(refusal == AIToolAccess.unidentifiedMessage)
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
                                                allow: { box.settings.allowedClients = AIToolAccess.allowing($0, in: box.settings.allowedClients) })
        async let second = consent.ensureAllowed(client, settings: { box.settings }, managed: false,
                                                 prompt: { _ in box.asked += 1; return true },
                                                 allow: { box.settings.allowedClients = AIToolAccess.allowing($0, in: box.settings.allowedClients) })
        let answers = await [first, second]
        #expect(answers == [nil, nil])
        #expect(box.asked == 1)
        #expect(box.settings.allowedClients.count == 1)
    }

    /// Security review note: a program copying itself to new paths can't fill the screen with questions.
    @Test func atMostThreeQuestionsAMinute() async {
        let clock = ConsentClock()
        let consent = AIToolConsent(now: { clock.now })
        var asked = 0
        for index in 0..<4 {
            let copy = AIToolClient(path: "/tmp/copy\(index)", displayName: "copy")
            let refusal = await consent.ensureAllowed(copy, settings: { AIToolsSettings() }, managed: false,
                                                      prompt: { _ in asked += 1; return false }, allow: { _ in })
            #expect(refusal != nil)
        }
        #expect(asked == 3)
        let fourth = await consent.ensureAllowed(AIToolClient(path: "/tmp/copy9", displayName: "copy"), settings: { AIToolsSettings() },
                                                 managed: false, prompt: { _ in asked += 1; return false }, allow: { _ in })
        #expect(fourth == AIToolConsent.tooManyMessage)
        clock.now = clock.now.addingTimeInterval(61)
        _ = await consent.ensureAllowed(AIToolClient(path: "/tmp/copy10", displayName: "copy"), settings: { AIToolsSettings() },
                                        managed: false, prompt: { _ in asked += 1; return false }, allow: { _ in })
        #expect(asked == 4)
    }
}

@MainActor
final class ConsentBox {
    var asked = 0
    var settings = AIToolsSettings()
}

@MainActor
final class ConsentClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

/// A process table for the tests.
struct FakeProcessTable: AIToolProcessTable {
    var processes: [Int32: AIToolProcess]

    init(_ list: [AIToolProcess]) {
        processes = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
    }

    func process(_ pid: Int32) -> AIToolProcess? { processes[pid] }
}

/// Upstream AiToolCaller: the program that started greenshot-mcp, shells skipped; the Mac's identity of runtimes (SM-H1).
@Suite struct AIToolCallerTests {
    private let server = AIToolProcess(pid: 500, parentPID: 400, startTime: 1000, path: "/Applications/G.app/Contents/Helpers/greenshot-mcp")
    private func unsigned(_ process: AIToolProcess) -> (name: String?, teamID: String?) { (nil, nil) }

    @Test func skipsShellsAndPinsTheScript() throws {
        let node = AIToolProcess(pid: 200, parentPID: 1, startTime: 700, path: "/opt/homebrew/bin/node",
                                 arguments: ["node", "--no-warnings", "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js", "--debug"],
                                 environment: ["HOME": "/Users/me"], workingDirectory: "/Users/me")
        let table = FakeProcessTable([server,
                                      AIToolProcess(pid: 400, parentPID: 300, startTime: 900, path: "/bin/zsh"),
                                      AIToolProcess(pid: 300, parentPID: 200, startTime: 800, path: "/usr/bin/env"), node])
        let client = try AIToolCaller.identify(serverPID: 500, table: table, signer: { _ in ("Dev", "TEAM123456") }).get()
        #expect(client.path == "/opt/homebrew/bin/node")
        #expect(client.displayName == "node")
        #expect(client.signer == "Dev")
        #expect(client.teamID == "TEAM123456")
        #expect(client.identity.script == "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js")
        #expect(client.key == "/opt/homebrew/bin/node | script: /opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js")
        #expect(client.serverProcessID == 500)
        #expect(client.serverStartTime == 1000)
    }

    @Test func refusesReusedAndOrphanedProcesses() {
        let reused = FakeProcessTable([server, AIToolProcess(pid: 400, parentPID: 1, startTime: 2000, path: "/Applications/X.app/Contents/MacOS/X")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: reused, signer: unsigned).get()) == nil)
        let orphan = FakeProcessTable([AIToolProcess(pid: 500, parentPID: 1, startTime: 1000, path: "/x/greenshot-mcp")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: orphan, signer: unsigned).get()) == nil)
        let onlyShells = FakeProcessTable([server, AIToolProcess(pid: 400, parentPID: 1, startTime: 900, path: "/bin/sh")])
        #expect((try? AIToolCaller.identify(serverPID: 500, table: onlyShells, signer: unsigned).get()) == nil)
    }

    @Test func stopsAfterFiveLaunchers() {
        var list = [server]
        for index in 0..<7 {
            let pid = Int32(400 - index)
            list.append(AIToolProcess(pid: pid, parentPID: pid - 1, startTime: UInt64(900 - index), path: "/bin/bash"))
        }
        list.append(AIToolProcess(pid: 393, parentPID: 1, startTime: 10, path: "/Applications/Tool.app/Contents/MacOS/Tool"))
        #expect((try? AIToolCaller.identify(serverPID: 500, table: FakeProcessTable(list), signer: unsigned).get()) == nil)
    }

    @Test func names() {
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Claude.app/Contents/MacOS/Claude") == "Claude")
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Claude.app/Contents/Helpers/disclaimer") == "Claude (disclaimer)")
        #expect(AIToolCaller.displayName(forExecutable: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper")
                == "Cursor (Cursor Helper)")
        #expect(AIToolCaller.displayName(forExecutable: "/Users/me/.local/share/claude/versions/2.1.0") == "claude (2.1.0)")
        #expect(AIToolCaller.displayName(forExecutable: "/usr/local/bin/codex") == "codex")
        // SM-L4: no line breaks or direction overrides from a file name
        #expect(AIToolCaller.displayName(forExecutable: "/tmp/Claude\u{202E}gpj.exe\nSigned by Apple") == "Claudegpj.exeSigned by Apple")
    }

    @Test func realTableKnowsThisProcess() throws {
        let me = try #require(SystemProcessTable().process(getpid()))
        #expect(me.pid == getpid())
        #expect(me.path != nil)
        #expect(me.startTime > 0)
        // KERN_PROCARGS2 of the same user: the arguments and the environment
        #expect(me.arguments?.isEmpty == false)
        #expect(me.environment?["HOME"] != nil)
        #expect(me.workingDirectory?.hasPrefix("/") == true)
    }
}

/// SM-H1: what is allowed when the user allows a runtime.
@Suite struct AIToolIdentityTests {
    private func identity(_ executable: String, _ arguments: [String], _ environment: [String: String] = [:]) -> Result<AIToolIdentity, AIToolError> {
        AIToolCaller.identity(executable: executable, arguments: arguments, environment: environment, workingDirectory: "/Users/me/project")
    }

    @Test func programsAreTheirExecutable() throws {
        let claude = try identity("/Applications/Claude.app/Contents/MacOS/Claude", ["Claude", "--whatever"]).get()
        #expect(claude.key == "/Applications/Claude.app/Contents/MacOS/Claude")
        #expect(claude.script == nil)
        // A program's arguments needn't be readable
        let unreadable = AIToolCaller.identity(executable: "/usr/local/bin/codex", arguments: nil, environment: nil)
        #expect((try? unreadable.get())?.key == "/usr/local/bin/codex")
    }

    @Test func runtimesAreTheirScript() throws {
        let node = try identity("/opt/homebrew/bin/node", ["node", "--require", "/tmp/hook.js", "cli.js", "--resume"]).get()
        #expect(node.script == "/Users/me/project/cli.js")
        #expect(node.notes == ["--require /tmp/hook.js"])
        let module = try identity("/usr/bin/python3", ["python3", "-u", "-m", "mcp_client"]).get()
        #expect(module.script == "-m mcp_client")
        let bun = try identity("/Users/me/.bun/bin/bun", ["bun", "run", "server.ts"]).get()
        #expect(bun.script == "/Users/me/project/server.ts")
        let deno = try identity("/opt/homebrew/bin/deno", ["deno", "run", "--allow-net", "main.ts"]).get()
        #expect(deno.script == "/Users/me/project/main.ts")
        let options = try identity("/opt/homebrew/bin/node", ["node", "/x/cli.js"], ["NODE_OPTIONS": "--require /tmp/evil.js"]).get()
        #expect(options.key == "/opt/homebrew/bin/node | script: /x/cli.js | NODE_OPTIONS: --require /tmp/evil.js")
    }

    @Test(arguments: [
        ("/opt/homebrew/bin/node", ["node", "-e", "require('child_process')"]),
        ("/opt/homebrew/bin/node", ["node", "--eval=1"]),
        ("/opt/homebrew/bin/node", ["node"]),
        ("/usr/bin/python3", ["python3", "-c", "print(1)"]),
        ("/usr/bin/ruby", ["ruby", "-e", "puts 1"]),
        ("/usr/bin/osascript", ["osascript", "-e", "beep"]),
        ("/opt/homebrew/bin/bun", ["bun", "--eval", "1"]),
    ])
    func inlineCodeIsRefused(executable: String, arguments: [String]) {
        #expect((try? identity(executable, arguments).get()) == nil)
    }

    @Test func runtimeSwitchesAndInjectionsChangeTheIdentity() throws {
        let electron = try identity("/Applications/Visual Studio Code.app/Contents/MacOS/Electron", ["Electron", "/tmp/x.js"],
                                    ["ELECTRON_RUN_AS_NODE": "1"]).get()
        #expect(electron.script == "/tmp/x.js")
        #expect(electron.notes.contains("as Node.js (ELECTRON_RUN_AS_NODE)"))
        let noScript = identity("/Applications/Cursor.app/Contents/MacOS/Cursor", ["Cursor", "-e", "1"], ["ELECTRON_RUN_AS_NODE": "1"])
        #expect((try? noScript.get()) == nil)
        let bunBinary = try identity("/Users/me/.local/share/claude/versions/2.1.0", ["claude", "/tmp/y.js"], ["BUN_BE_BUN": "1"]).get()
        #expect(bunBinary.notes.contains("as Bun (BUN_BE_BUN)"))
        let injected = identity("/Applications/Claude.app/Contents/MacOS/Claude", ["Claude"], ["DYLD_INSERT_LIBRARIES": "/tmp/x.dylib"])
        #expect((try? injected.get()) == nil)
        // Without arguments a runtime can't be pinned down
        #expect((try? AIToolCaller.identity(executable: "/opt/homebrew/bin/node", arguments: nil, environment: [:]).get()) == nil)
    }

    @Test func allowedEntriesMatchIdentityAndTeam() {
        let signed = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude", teamID: "Q6L2SF6YDW")
        let replaced = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude", teamID: nil)
        let entry = AIToolAllowedEntry(parsing: "/Applications/Claude.app/Contents/MacOS/Claude | Team ID: Q6L2SF6YDW")
        #expect(entry.key == "/Applications/Claude.app/Contents/MacOS/Claude")
        #expect(entry.teamID == "Q6L2SF6YDW")
        #expect(entry.matches(signed))
        // The allowed executable now isn't signed by that team: asked again
        #expect(!entry.matches(replaced))
        // A plain path (older settings, an administrator's list) matches the executable whoever signed it
        #expect(AIToolAllowedEntry(parsing: "/applications/claude.app/contents/macos/claude").matches(replaced))
        // Allowing node for one script doesn't allow another script
        let script = AIToolIdentity(executable: "/opt/homebrew/bin/node", script: "/x/cli.js")
        let other = AIToolIdentity(executable: "/opt/homebrew/bin/node", script: "/tmp/evil.js")
        var settings = AIToolsSettings()
        settings.allowedClients = AIToolAccess.allowing(AIToolClient(path: "/opt/homebrew/bin/node", displayName: "node", identity: script), in: ["/opt/homebrew/bin/node"])
        #expect(settings.allowedClients == ["/opt/homebrew/bin/node", "/opt/homebrew/bin/node | script: /x/cli.js"])
        #expect(AIToolAccess.isAllowed(AIToolClient(path: "/opt/homebrew/bin/node", displayName: "node", identity: script), settings: settings))
        #expect(!AIToolAccess.isAllowed(AIToolClient(path: "/opt/homebrew/bin/node", displayName: "node", identity: other), settings: settings))
        #expect(AIToolAllowedEntry(parsing: settings.allowedClients[1]).script == "/x/cli.js")
        // Allowing again replaces the entry of the same identity
        let resigned = AIToolAccess.allowing(signed, in: ["/Applications/Claude.app/Contents/MacOS/Claude | Team ID: OLDTEAM000"])
        #expect(resigned == ["/Applications/Claude.app/Contents/MacOS/Claude | Team ID: Q6L2SF6YDW"])
    }

    @Test func processArgumentsBuffer() throws {
        var bytes: [UInt8] = [3, 0, 0, 0]
        bytes += Array("/opt/homebrew/bin/node".utf8) + [0, 0, 0]
        for text in ["node", "cli.js", "--x", "HOME=/Users/me", "NODE_OPTIONS=--a=b", ""] { bytes += Array(text.utf8) + [0] }
        let parsed = try #require(AIToolCaller.parseProcessArguments(bytes))
        #expect(parsed.arguments == ["node", "cli.js", "--x"])
        #expect(parsed.environment["HOME"] == "/Users/me")
        #expect(parsed.environment["NODE_OPTIONS"] == "--a=b")
        #expect(AIToolCaller.parseProcessArguments([1, 0]) == nil)
    }

    @Test func displayedTextIsCleaned() {
        #expect(AIToolText.displayed("a\nb\u{2028}c\u{202E}d\u{0007}e") == "abcde")
        #expect(AIToolText.displayed(String(repeating: "x", count: 10), limit: 4) == "xxxx…")
    }

    @Test func clickjackingGuard() {
        let question = CGRect(x: 100, y: 100, width: 400, height: 200)
        let own = ConsentClickGuard.WindowAbove(ownerPID: 42, frame: question, alpha: 1)
        let other = ConsentClickGuard.WindowAbove(ownerPID: 7, frame: CGRect(x: 450, y: 250, width: 100, height: 100), alpha: 1)
        let invisible = ConsentClickGuard.WindowAbove(ownerPID: 7, frame: question, alpha: 0)
        let beside = ConsentClickGuard.WindowAbove(ownerPID: 7, frame: CGRect(x: 600, y: 100, width: 50, height: 50), alpha: 1)
        #expect(!ConsentClickGuard.isCovered(question, by: [own, invisible, beside], ownPID: 42))
        #expect(ConsentClickGuard.isCovered(question, by: [other], ownPID: 42))
    }
}

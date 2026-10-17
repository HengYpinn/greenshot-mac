// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// What the user allows when they allow an AI tool (Mac addition to upstream's executable path, security review SM-H1):
/// for a program its executable; for a runtime that runs any script it is given (node, bun, deno, python, ruby, perl, php,
/// osascript, and an Electron app or bun binary switched into such a runtime with ELECTRON_RUN_AS_NODE / BUN_BE_BUN) the
/// runtime *and its script*, plus NODE_OPTIONS when set. So allowing "node running Claude Code's cli.js" doesn't allow
/// every other node script.
public struct AIToolIdentity: Equatable, Sendable {
    public var executable: String
    /// The script a runtime runs ("-m module" for python), resolved; nil for a program.
    public var script: String?
    /// The options before the script that change what runs (preloaded modules, NODE_OPTIONS, runtime switch).
    public var notes: [String]

    public init(executable: String, script: String? = nil, notes: [String] = []) {
        self.executable = executable
        self.script = script
        self.notes = notes
    }

    /// The text kept in `AIToolsSettings.allowedClients` (without the Team ID): "<executable> | script: <script> | <note>".
    public var key: String {
        var parts = [executable]
        if let script { parts.append("script: \(script)") }
        parts += notes
        return parts.joined(separator: AIToolAllowedEntry.separator)
    }
}

/// One line of `AIToolsSettings.allowedClients`: the identity key and, for a program signed by a developer, its Team ID
/// ("… | Team ID: ABCDE12345"). A program whose identity matches but whose running code isn't signed by that team (an
/// allowed executable replaced by another one) is asked about again. Plain paths (older settings, an administrator's
/// list) match by the executable alone.
public struct AIToolAllowedEntry: Equatable, Sendable {
    static let separator = " | "
    static let teamLabel = "Team ID: "

    public var key: String
    public var teamID: String?

    public init(key: String, teamID: String?) {
        self.key = key
        self.teamID = teamID
    }

    public init(parsing line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: Self.separator + Self.teamLabel, options: .backwards) {
            key = String(text[..<range.lowerBound])
            let team = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            teamID = team.isEmpty ? nil : team
        } else {
            key = text
            teamID = nil
        }
    }

    public var line: String { teamID.map { key + Self.separator + Self.teamLabel + $0 } ?? key }

    /// The executable at the start of the key.
    public var executable: String { key.components(separatedBy: Self.separator).first ?? key }

    /// The script part of the key, if any.
    public var script: String? {
        key.components(separatedBy: Self.separator).dropFirst().first { $0.hasPrefix("script: ") }.map { String($0.dropFirst("script: ".count)) }
    }

    /// The identity matches (any case) and, when the entry names a team, the running program is signed by it.
    public func matches(_ client: AIToolClient) -> Bool {
        guard key.caseInsensitiveCompare(client.identity.key) == .orderedSame else { return false }
        guard let teamID else { return true }
        return client.teamID == teamID
    }
}

extension AIToolCaller {
    /// Runtimes that run whatever script they are given.
    enum Runtime: String {
        case node = "Node.js", bun = "Bun", deno = "Deno", python = "Python", ruby = "Ruby", perl = "Perl", php = "PHP"
        case osascript = "AppleScript (osascript)"
    }

    static func runtime(ofExecutable path: String) -> Runtime? {
        let name = (path as NSString).lastPathComponent.lowercased()
        switch name {
        case "node", "nodejs": return .node
        case "bun": return .bun
        case "deno": return .deno
        case "ruby": return .ruby
        case "php": return .php
        case "osascript": return .osascript
        default:
            if name == "python" || name.hasPrefix("python2") || name.hasPrefix("python3") { return .python }
            if name == "perl" || name.hasPrefix("perl5") { return .perl }
            return nil
        }
    }

    /// The identity of the program behind greenshot-mcp from its executable, arguments, environment and working directory
    /// (SM-H1); refused for code that can't be pinned down: DYLD_ variables (injected libraries), inline code (`node -e`,
    /// `python -c`), a runtime without a script (stdin, a REPL), or arguments that can't be read.
    public static func identity(executable: String, arguments: [String]?, environment: [String: String]?,
                                workingDirectory: String? = nil) -> Result<AIToolIdentity, AIToolError> {
        let name = (executable as NSString).lastPathComponent
        let environment = environment ?? [:]
        if environment.keys.contains(where: { $0.hasPrefix("DYLD_") }) {
            return .failure(AIToolError("\(name) was started with DYLD_ variables, which can change any program: it can't use Greenshot for Mac."))
        }
        var notes: [String] = []
        var runtime = runtime(ofExecutable: executable)
        if let value = environment["ELECTRON_RUN_AS_NODE"], !value.isEmpty, value != "0" {
            runtime = .node
            notes.append("as Node.js (ELECTRON_RUN_AS_NODE)")
        }
        if let value = environment["BUN_BE_BUN"], !value.isEmpty, value != "0", runtime != .bun {
            runtime = .bun
            notes.append("as Bun (BUN_BE_BUN)")
        }
        guard let runtime else { return .success(AIToolIdentity(executable: executable)) }
        guard let arguments, !arguments.isEmpty else {
            return .failure(AIToolError("Greenshot for Mac could not read the arguments of \(name) (\(runtime.rawValue)), so it can't tell which script asks."))
        }
        if runtime == .node || runtime == .bun, let options = environment["NODE_OPTIONS"]?.trimmingCharacters(in: .whitespaces), !options.isEmpty {
            notes.append("NODE_OPTIONS: \(options)")
        }
        switch script(of: runtime, arguments: Array(arguments.dropFirst())) {
        case .failure(let error):
            return .failure(AIToolError("\(name) (\(runtime.rawValue)) \(error.message): it can't use Greenshot for Mac."))
        case .success(let parsed):
            let script = resolve(parsed.script, workingDirectory: workingDirectory)
            return .success(AIToolIdentity(executable: executable, script: script, notes: parsed.options + notes))
        }
    }

    /// The script and the options before it that change what runs (`--require x`).
    static func script(of runtime: Runtime, arguments: [String]) -> Result<(script: String, options: [String]), AIToolError> {
        let inline: Set<String>
        let withValue: Set<String>
        let codeLoading: Set<String>
        var subcommands: Set<String> = []
        switch runtime {
        case .node:
            inline = ["-e", "--eval", "-p", "--print", "-i", "--interactive", "-"]
            withValue = ["-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions", "--env-file", "--input-type",
                         "--title", "--inspect-port", "--disable-warning"]
            codeLoading = ["-r", "--require", "--import", "--loader", "--experimental-loader"]
        case .bun:
            inline = ["-e", "--eval", "-p", "--print", "-"]
            withValue = ["-r", "--preload", "--require", "--import", "--cwd", "--env-file", "--config", "-c"]
            codeLoading = ["-r", "--preload", "--require", "--import"]
            subcommands = ["run"]
        case .deno:
            inline = ["eval", "repl", "-"]
            withValue = ["--config", "-c", "--import-map", "--location", "--env-file", "--cert"]
            codeLoading = ["--import-map", "--preload"]
            subcommands = ["run", "serve"]
        case .python:
            inline = ["-c", "-"]
            withValue = ["-W", "-X", "-Q"]
            codeLoading = []
        case .ruby:
            inline = ["-e", "-"]
            withValue = ["-r", "-I", "-C", "-E", "--encoding"]
            codeLoading = ["-r"]
        case .perl:
            inline = ["-e", "-E", "-"]
            withValue = ["-I"]
            codeLoading = []
        case .php:
            inline = ["-r", "-a", "-"]
            withValue = ["-c", "-d", "-z"]
            codeLoading = ["-z"]
        case .osascript:
            inline = ["-e", "-"]
            withValue = ["-l", "-s"]
            codeLoading = []
        }
        var options: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let flag = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
            if inline.contains(argument) || inline.contains(flag) {
                return .failure(AIToolError("runs code given on its command line or from standard input"))
            }
            if runtime == .python, argument == "-m" {
                guard index + 1 < arguments.count else { return .failure(AIToolError("names no module to run")) }
                return .success(("-m \(arguments[index + 1])", options))
            }
            if runtime == .php, argument == "-f" {
                guard index + 1 < arguments.count else { return .failure(AIToolError("names no script")) }
                return .success((arguments[index + 1], options))
            }
            if subcommands.contains(argument), options.isEmpty || index == 0 {
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                let takesValue = withValue.contains(argument)
                if codeLoading.contains(flag) {
                    options.append(takesValue && index + 1 < arguments.count ? "\(argument) \(arguments[index + 1])" : argument)
                }
                index += takesValue ? 2 : 1
                continue
            }
            return .success((argument, options))
        }
        return .failure(AIToolError("runs no script file"))
    }

    /// The script's real path (symbolic links resolved, relative to the program's working directory); "-m module" and
    /// unreadable paths stay as written.
    static func resolve(_ script: String, workingDirectory: String?) -> String {
        guard !script.hasPrefix("-m ") else { return script }
        var path = script
        if !path.hasPrefix("/"), let workingDirectory, workingDirectory.hasPrefix("/") {
            path = (workingDirectory as NSString).appendingPathComponent(path)
        }
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return path }
        return IPCEndpoint.realPath((path as NSString).standardizingPath)
    }

    /// The arguments and environment in a `KERN_PROCARGS2` buffer: the argument count, the executable path, padding,
    /// the arguments, then the environment, each NUL-terminated.
    static func parseProcessArguments(_ bytes: [UInt8]) -> (arguments: [String], environment: [String: String])? {
        guard bytes.count > 4 else { return nil }
        let count = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        var index = 4
        // The executable path, then NUL padding
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        func next() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return text
        }
        var arguments: [String] = []
        for _ in 0..<count {
            guard let argument = next() else { return nil }
            arguments.append(argument)
        }
        var environment: [String: String] = [:]
        while let entry = next(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return (arguments, environment)
    }

    /// The system's `KERN_PROCARGS2` of a process of the same user.
    static func processArguments(_ pid: Int32) -> (arguments: [String], environment: [String: String])? {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var limit = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&limit, 2, &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        var length = Int(maximum)
        var name = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&name, 3, &buffer, &length, nil, 0) == 0 else { return nil }
        return parseProcessArguments(Array(buffer.prefix(length)))
    }

    /// The working directory of a process of the same user.
    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Text from another program shown in a question or banner (SM-L4): no control, format (bidirectional overrides),
/// line or paragraph separators, and at most `limit` characters.
public enum AIToolText {
    public static func displayed(_ text: String, limit: Int = 200) -> String {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        }))
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)) + "…"
    }
}

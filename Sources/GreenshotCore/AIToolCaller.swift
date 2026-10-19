// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// A process as the AI tool identification sees it.
public struct AIToolProcess: Equatable, Sendable {
    public var pid: Int32
    public var parentPID: Int32
    /// When it started, microseconds since 1970 (a parent must have started before its child: pids are reused).
    public var startTime: UInt64
    /// Its executable, nil when it can't be read.
    public var path: String?
    /// Its arguments (the first is how it was started), environment and working directory; nil when they can't be read.
    public var arguments: [String]?
    public var environment: [String: String]?
    public var workingDirectory: String?
    /// The kernel's unique id of the process (kept by an exec) and its `p_idversion` (a global counter the kernel raises at
    /// every fork and every exec), nil when they can't be read. A process that started a child before it exec'd another
    /// program has a newer version than that child (exec swap, see `AIToolCaller.clientProcess`).
    public var uniqueID: UInt64?
    public var idVersion: Int32?

    public init(pid: Int32, parentPID: Int32, startTime: UInt64, path: String?, arguments: [String]? = nil,
                environment: [String: String]? = nil, workingDirectory: String? = nil, uniqueID: UInt64? = nil, idVersion: Int32? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTime = startTime
        self.path = path
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.uniqueID = uniqueID
        self.idVersion = idVersion
    }
}

/// Where the processes come from (the system's, or a table in tests).
public protocol AIToolProcessTable: Sendable {
    func process(_ pid: Int32) -> AIToolProcess?
}

/// `struct proc_uniqidentifierinfo` of <sys/proc_info.h> (56 bytes), which Swift doesn't import.
private struct UniqueIdentifierInfo {
    var p_uuid: (UInt64, UInt64) = (0, 0)
    var p_uniqueid: UInt64 = 0
    var p_puniqueid: UInt64 = 0
    var p_idversion: Int32 = 0
    var p_reserve2: UInt32 = 0
    var p_reserve3: UInt64 = 0
    var p_reserve4: UInt64 = 0
}

/// The system's processes (`proc_pidinfo` with `PROC_PIDTBSDINFO`, `proc_pidpath`, `KERN_PROCARGS2`,
/// `PROC_PIDVNODEPATHINFO`, `PROC_PIDUNIQIDENTIFIERINFO`; the arguments and the working directory only for processes of
/// the same user).
public struct SystemProcessTable: AIToolProcessTable {
    public init() {}

    public func process(_ pid: Int32) -> AIToolProcess? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let start = UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        let details = AIToolCaller.processArguments(pid)
        var unique = UniqueIdentifierInfo()
        let uniqueSize = Int32(MemoryLayout<UniqueIdentifierInfo>.size)
        let hasUnique = proc_pidinfo(pid, 17 /* PROC_PIDUNIQIDENTIFIERINFO, not exported to Swift */, 0, &unique, uniqueSize) == uniqueSize
        return AIToolProcess(pid: pid, parentPID: Int32(info.pbi_ppid), startTime: start, path: path, arguments: details?.arguments,
                             environment: details?.environment, workingDirectory: AIToolCaller.workingDirectory(pid),
                             uniqueID: hasUnique ? unique.p_uniqueid : nil, idVersion: hasUnique ? unique.p_idversion : nil)
    }
}

/// Which program is behind greenshot-mcp (upstream `Ai/AiToolCaller.cs`): the AI tool is the program that started it,
/// shells in between are skipped. The connection itself was already checked to be greenshot-mcp from the app's bundle
/// (`IPCPeerPolicy`, by the audit token).
public enum AIToolCaller {
    /// Programs that only run the AI tool's command (upstream: cmd.exe, PowerShell); the AI tool is their parent. Node
    /// is not one of them: an AI tool installed with npm runs in node (upstream names it "Node.js"). A program with such
    /// a name is skipped only when it is a system binary that starts greenshot-mcp directly (`isLauncher`): a shell
    /// that runs a script file is that script's program, and any other file named `sh` is just a program.
    public static let launcherNames: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "tcsh", "csh", "fish", "env", "login"]
    static let shellNames: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "tcsh", "csh", "fish"]
    public static let maximumLauncherDepth = 5
    static let serverName = "greenshot-mcp"

    /// Who signed a running program, checked on the running code (SM-H1): the certificate's name and the Team ID; nil
    /// for an unsigned, ad hoc signed or modified program.
    public typealias SignerCheck = (AIToolProcess) -> (name: String?, teamID: String?)

    /// The AI tool behind greenshot-mcp's process `serverPID`; else why it can't be identified or isn't allowed to ask.
    public static func identify(serverPID: Int32, table: any AIToolProcessTable, signer: SignerCheck) -> Result<AIToolClient, AIToolError> {
        guard let server = table.process(serverPID) else { return .failure(AIToolError(AIToolAccess.unidentifiedMessage)) }
        guard let process = clientProcess(of: server, table: table), let path = process.path else {
            return .failure(AIToolError(AIToolAccess.unidentifiedMessage))
        }
        let identity: AIToolIdentity
        switch self.identity(executable: path, arguments: process.arguments, environment: process.environment,
                             workingDirectory: process.workingDirectory) {
        case .success(let found): identity = found
        case .failure(let error): return .failure(error)
        }
        let signature = signer(process)
        let client = AIToolClient(path: path, displayName: displayName(forExecutable: path), signer: signature.name,
                                  teamID: signature.teamID, identity: identity, serverProcessID: server.pid, serverStartTime: server.startTime)
        return .success(client)
    }

    /// The executable of the program that started `server`, launchers skipped; nil when the chain ends (launchd, an
    /// exited parent whose child went to launchd) or a parent started after its child (a reused process id).
    public static func clientPath(of server: AIToolProcess, table: any AIToolProcessTable) -> String? {
        clientProcess(of: server, table: table)?.path
    }

    /// The process of the program that started `server`, launchers skipped. Nil (not identified) when the walk reaches
    /// pid 1 (greenshot-mcp's parent exited), a parent started after its child (a reused process id), a parent has a newer
    /// `p_idversion` than its child, or a launcher that isn't a plain command wrapper has no program behind it.
    ///
    /// The `p_idversion` check catches an exec swap: a program starts greenshot-mcp as its child with the pipes it holds,
    /// then `exec`s an allowed program (an exec keeps the start time, so the parent looks as old as ever). In a normal chain
    /// every ancestor exec'd before it started its child, so its version is older. This can't stop a program that forks
    /// first and lets the child start greenshot-mcp after the parent became the allowed program: a program that can
    /// control an allowed program can use it (documented limit).
    public static func clientProcess(of server: AIToolProcess, table: any AIToolProcessTable) -> AIToolProcess? {
        var child = server
        for _ in 0...maximumLauncherDepth {
            guard child.parentPID > 1, let parent = table.process(child.parentPID), parent.startTime <= child.startTime,
                  let path = parent.path, !path.isEmpty else { return nil }
            if let parentVersion = parent.idVersion, let childVersion = child.idVersion, parentVersion > childVersion { return nil }
            if isLauncher(parent, starting: child) {
                child = parent
                continue
            }
            // A shell running a script is that script's program (`sh | script: …`); env or login without a command isn't one
            let name = (path as NSString).lastPathComponent.lowercased()
            if launcherNames.contains(name), !shellNames.contains(name) { return nil }
            return parent
        }
        return nil
    }

    /// Whether `process` only wraps the command that starts `child` (greenshot-mcp, or a launcher already skipped): a
    /// binary of the system in /bin or /usr/bin (a file named `sh` anywhere else is not one) whose arguments name that
    /// command first: `sh -c "exec greenshot-mcp"` (also `-lc`, `-ic`), `env VAR=1 greenshot-mcp`, `login … greenshot-mcp`.
    /// A shell that runs a script file, or a command other than greenshot-mcp, is not skipped.
    public static func isLauncher(_ process: AIToolProcess, starting child: AIToolProcess) -> Bool {
        guard let path = process.path, let arguments = process.arguments, !arguments.isEmpty else { return false }
        let name = (path as NSString).lastPathComponent.lowercased()
        guard launcherNames.contains(name), isSystemBinary(path) else { return false }
        // greenshot-mcp itself, or the launcher below that was already skipped (`zsh -c "sh -c 'exec greenshot-mcp'"`)
        let childName = child.path.map { ($0 as NSString).lastPathComponent.lowercased() } ?? ""
        let target = launcherNames.contains(childName) ? childName : serverName
        let rest = Array(arguments.dropFirst())
        let command: String?
        switch name {
        case "env": command = envCommand(rest)
        case "login": command = loginCommand(rest)
        default: command = shellCommand(rest)
        }
        guard let command else { return false }
        return (command as NSString).lastPathComponent.lowercased() == target
    }

    /// In /bin or /usr/bin, by the path as written and by its real path (symbolic links resolved).
    static func isSystemBinary(_ path: String) -> Bool {
        func inSystem(_ path: String) -> Bool { path.hasPrefix("/bin/") || path.hasPrefix("/usr/bin/") }
        return inSystem(path) && inSystem(IPCEndpoint.realPath(path))
    }

    /// The first word of the command of `sh -c "…"`: after the option clusters (`-l`, `-lc`, `-ic`, `--login`), the
    /// argument after the one with `c`; nil when the shell runs a script file or reads standard input instead.
    static func shellCommand(_ arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { return nil }
            guard argument.hasPrefix("-") || argument.hasPrefix("+") else { return nil }
            if ["-o", "+o", "-O", "+O", "--rcfile", "--init-file"].contains(argument) {
                index += 2
                continue
            }
            if !argument.hasPrefix("--"), argument.dropFirst().contains("s") { return nil }
            if !argument.hasPrefix("--"), argument.hasPrefix("-"), argument.dropFirst().contains("c") {
                guard index + 1 < arguments.count else { return nil }
                return commandWord(arguments[index + 1])
            }
            index += 1
        }
        return nil
    }

    /// The program of `env [options] [VAR=value…] program …`.
    static func envCommand(_ arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-S" || argument.hasPrefix("-S") || argument == "--" { return nil }
            if ["-u", "-P", "-C"].contains(argument) {
                index += 2
            } else if argument.hasPrefix("-") || isAssignment(argument) {
                index += 1
            } else {
                return argument
            }
        }
        return nil
    }

    /// The program of `login [-pfl…] [-h host] user program …`.
    static func loginCommand(_ arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("-") { index += arguments[index] == "-h" ? 2 : 1 }
        index += 1 // the user name
        guard index < arguments.count else { return nil }
        return arguments[index]
    }

    /// The first word that runs something in a shell command line, after `exec` and `VAR=value` assignments; quoted
    /// words (a path with spaces) are one word. Nil for an empty command.
    static func commandWord(_ command: String) -> String? {
        for word in shellWords(command) {
            if word == "exec" || isAssignment(word) { continue }
            return word
        }
        return nil
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[..<equals]
        return name.first.map { $0.isLetter || $0 == "_" } == true && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Words of a command line split at blanks, with single quotes, double quotes and backslashes removed (enough to find
    /// the first words; no expansion).
    static func shellWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var started = false
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                started = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                started = true
            } else if character == " " || character == "\t" || character == "\n" {
                if started { words.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { words.append(current) }
        return words
    }

    /// The name to show: the app the executable belongs to (its outermost `.app`), "App (helper)" when it is a helper
    /// of the app rather than its main program (upstream names Antigravity's language_server "Antigravity
    /// (language_server)"), else the file name.
    public static func displayName(forExecutable path: String) -> String {
        AIToolText.displayed(rawDisplayName(forExecutable: path), limit: 80)
    }

    static func rawDisplayName(forExecutable path: String) -> String {
        let file = (path as NSString).lastPathComponent
        let components = (path as NSString).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else {
            // A versioned install like ~/.local/share/claude/versions/2.1.0: the program's folder names it
            guard file.first?.isNumber == true else { return file }
            let generic: Set<String> = ["versions", "version", "bin", "libexec", "current", "latest", "releases"]
            let owner = components.dropLast().last { component in
                component != "/" && component.first?.isNumber != true && !generic.contains(component.lowercased())
            }
            return owner.map { "\($0) (\(file))" } ?? file
        }
        let appPath = NSString.path(withComponents: Array(components[...appIndex]))
        let folderName = (components[appIndex] as NSString).deletingPathExtension
        let info = Bundle(path: appPath)?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? folderName
        let mainExecutable = info?["CFBundleExecutable"] as? String ?? folderName
        let isMain = file == mainExecutable && components.count == appIndex + 4 && components[appIndex + 2] == "MacOS"
        return isMain ? name : "\(name) (\(file))"
    }
}

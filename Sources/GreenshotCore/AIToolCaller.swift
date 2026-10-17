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

    public init(pid: Int32, parentPID: Int32, startTime: UInt64, path: String?, arguments: [String]? = nil,
                environment: [String: String]? = nil, workingDirectory: String? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTime = startTime
        self.path = path
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// Where the processes come from (the system's, or a table in tests).
public protocol AIToolProcessTable: Sendable {
    func process(_ pid: Int32) -> AIToolProcess?
}

/// The system's processes (`proc_pidinfo` with `PROC_PIDTBSDINFO`, `proc_pidpath`, `KERN_PROCARGS2`,
/// `PROC_PIDVNODEPATHINFO`; the last two only for processes of the same user).
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
        return AIToolProcess(pid: pid, parentPID: Int32(info.pbi_ppid), startTime: start, path: path, arguments: details?.arguments,
                             environment: details?.environment, workingDirectory: AIToolCaller.workingDirectory(pid))
    }
}

/// Which program is behind greenshot-mcp (upstream `Ai/AiToolCaller.cs`): the AI tool is the program that started it,
/// shells in between are skipped. The connection itself was already checked to be greenshot-mcp from the app's bundle
/// (`IPCPeerPolicy`, by the audit token).
public enum AIToolCaller {
    /// Programs that only run the AI tool's command (upstream: cmd.exe, PowerShell); the AI tool is their parent. Node
    /// is not one of them: an AI tool installed with npm runs in node (upstream names it "Node.js").
    public static let launcherNames: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "tcsh", "csh", "fish", "env", "login"]
    public static let maximumLauncherDepth = 5

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

    /// The process of the program that started `server`, launchers skipped.
    public static func clientProcess(of server: AIToolProcess, table: any AIToolProcessTable) -> AIToolProcess? {
        var child = server
        for _ in 0...maximumLauncherDepth {
            guard child.parentPID > 1, let parent = table.process(child.parentPID), parent.startTime <= child.startTime,
                  let path = parent.path, !path.isEmpty else { return nil }
            if !isLauncher(path) { return parent }
            child = parent
        }
        return nil
    }

    public static func isLauncher(_ path: String) -> Bool {
        launcherNames.contains((path as NSString).lastPathComponent.lowercased())
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

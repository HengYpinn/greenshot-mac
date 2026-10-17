// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// The automation protocol of the app (upstream `Greenshot/Ipc/IpcEnvelope.cs`, `greenshot-proxy/protocol.h`,
// docs/greenshot-proxy-and-integration.md §2.1): length-prefixed JSON frames on a per-user unix domain socket instead of
// upstream's named pipe. The first frame of a connection is HELLO; it binds the connection's source.

/// Who sends a command. Socket clients announce theirs in HELLO; the app's own callers (links, Finder, AppleScript,
/// Services, Shortcuts) dispatch in-process with theirs. Each command lists the sources that may use it (`IPCWhitelist`).
public enum IPCSource: String, CaseIterable, Sendable {
    /// greenshot-cli, or a second start of the app forwarding its command line.
    case cli
    /// A `greenshotmac:` link (any web page can open one).
    case urlScheme = "url_scheme"
    /// Files opened with the app in Finder, dropped on its Dock icon or given to `open -a`.
    case openWith = "open_with"
    /// The browser extension's native messaging host (wave 4).
    case nativeMessaging = "native_messaging"
    /// The MCP server for AI tools (wave 4).
    case mcp
    /// Mac only: the AppleScript dictionary.
    case appleScript = "applescript"
    /// Mac only: the Services menu.
    case services
    /// Mac only: Shortcuts, Siri and Spotlight actions (App Intents).
    case shortcuts

    /// Upstream's names, any case.
    public init?(name: String?) {
        guard let name else { return nil }
        self.init(rawValue: name.lowercased())
    }
}

/// How replies are sent on a connection, announced in HELLO.
public enum IPCReplyFormat: String, Sendable {
    /// JSON objects, as the handlers produce them (browser extension, MCP).
    case json
    /// Text frames for a terminal: 'O' stdout, 'E' stderr, 'X' exit code.
    case text
}

/// The commands (upstream `IpcSecurityDispatcher.AllowedCommands`, plus the Mac's own).
public enum IPCCommand {
    public static let hello = "HELLO"
    public static let cli = "CLI"
    public static let watch = "WATCH"
    public static let urlScheme = "URL_SCHEME"
    public static let openFile = "OPEN_FILE"
    public static let exit = "EXIT"
    public static let reloadConfig = "RELOAD_CONFIG"
    public static let firstLaunch = "FIRST_LAUNCH"
    public static let version = "VERSION"
    public static let settings = "SETTINGS"
    public static let about = "ABOUT"
    public static let selfService = "SELF_SERVICE"
    public static let logViewer = "LOG_VIEWER"
    public static let runRecipe = "RUN_RECIPE"
    public static let listRecipes = "LIST_RECIPES"
    public static let describeRecipe = "DESCRIBE_RECIPE"
    public static let recipeEditor = "RECIPE_EDITOR"
    public static let recipeManager = "RECIPE_MANAGER"
    /// Mac only: a screenshot (`mode` parameter, see `AutomationCaptureMode`).
    public static let capture = "CAPTURE"
    /// Mac only: the image on the clipboard in the editor.
    public static let openClipboard = "OPEN_CLIPBOARD"
    // AI tools, only for greenshot-mcp (upstream `AiToolsIpcExtension.AiToolCommands`).
    /// The windows and displays, with window ids for Window arguments.
    public static let listWindows = "LIST_WINDOWS"
    /// The recipes with an AI tool trigger: greenshot-mcp's tools.
    public static let listAITools = "LIST_AI_TOOLS"
    /// Runs such a recipe and replies with its result and image.
    public static let runAITool = "RUN_AI_TOOL"
    /// What recipes can use here, or the JSON of one recipe.
    public static let recipeCatalog = "RECIPE_CATALOG"
    /// Checks a recipe without saving or showing it.
    public static let validateRecipe = "VALIDATE_RECIPE"
    /// Shows a new or changed recipe for the user's approval.
    public static let proposeRecipe = "PROPOSE_RECIPE"

    /// The commands only greenshot-mcp may use (upstream `AiToolsIpcExtension.IsAllowedForSource`).
    public static let aiToolCommands: Set<String> = [listWindows, listAITools, runAITool, recipeCatalog, validateRecipe,
                                                     proposeRecipe]
}

/// Exit codes of greenshot-cli (upstream `greenshot-proxy/protocol.h`, docs §2.1 "Command line").
public enum IPCExitCode {
    public static let ok: Int32 = 0
    public static let failure: Int32 = 1
    /// An invalid command line (upstream `CliCommandParser.UsageExitCode`).
    public static let usage: Int32 = 2
    /// The app isn't running and couldn't be started.
    public static let unavailable: Int32 = 3
}

/// The protocol version in every envelope (upstream `IPC_PROTOCOL_VERSION`).
public let ipcProtocolVersion = 1

/// One frame's JSON (upstream `IpcEnvelope`): a command with its arguments. Unknown members are kept in `extra`, so a
/// later client's fields reach the handlers that know them.
public struct IPCEnvelope: Equatable, Sendable {
    public var version = ipcProtocolVersion
    public var command: String?
    /// The source a client claims; the server replaces it with the source of the connection's HELLO.
    public var source: String?
    /// HELLO only: "json" (default) or "text".
    public var replyFormat: String?
    /// HELLO only: the client program and its version.
    public var client: String?
    public var clientVersion: String?
    /// HELLO only: the browser extension's origin (native messaging, wave 4).
    public var origin: String?
    /// The caller's working directory, for relative paths.
    public var cwd: String?
    /// CLI only: the unparsed arguments, without the program name.
    public var argv: [String]?
    /// URL_SCHEME only: the link.
    public var rawInput: String?
    public var files: [String] = []
    /// Command parameters (`tab`, `section`, `search`, `mode`, ...), looked up case-insensitively.
    public private(set) var parameters: [String: String] = [:]
    public var recipe: String?
    /// The caller wants the final reply as one JSON document (`--json`).
    public var json = false
    public var query: String?
    public var async = false
    public var extra: JSONObject = [:]

    public init(command: String? = nil, source: String? = nil) {
        self.command = command
        self.source = source
    }

    public var isHello: Bool { command?.uppercased() == IPCCommand.hello }

    /// HELLO, the first frame of every connection (upstream `IpcEnvelope.CreateHello`, proxy `SendHello`).
    public static func hello(source: IPCSource, replyFormat: IPCReplyFormat, client: String, clientVersion: String,
                             origin: String? = nil) -> IPCEnvelope {
        var hello = IPCEnvelope(command: IPCCommand.hello, source: source.rawValue)
        hello.replyFormat = replyFormat.rawValue
        hello.client = client
        hello.clientVersion = clientVersion
        hello.origin = origin
        return hello
    }

    /// An unparsed command line (upstream `IpcEnvelope.CreateCli`): what greenshot-cli sends.
    public static func commandLine(_ argv: [String], cwd: String?) -> IPCEnvelope {
        var envelope = IPCEnvelope(command: IPCCommand.cli)
        envelope.cwd = cwd
        envelope.argv = argv
        return envelope
    }

    /// A parameter, any case of its name.
    public func parameter(_ name: String) -> String? {
        if let exact = parameters[name] { return exact }
        return parameters.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Sets a parameter, replacing one of the same name in another case (the last one wins).
    public mutating func setParameter(_ name: String, _ value: String) {
        for key in parameters.keys where key.caseInsensitiveCompare(name) == .orderedSame {
            parameters.removeValue(forKey: key)
        }
        parameters[name] = value
    }

    // MARK: JSON

    private static let knownKeys: Set<String> = ["version", "command", "source", "reply_format", "client", "client_version",
                                                 "origin", "cwd", "argv", "raw_input", "files", "parameters", "recipe",
                                                 "json", "query", "async"]

    /// Reads the members it knows (wrong types count as missing, like a lenient deserializer); the rest go to `extra`.
    public init(json object: JSONObject) {
        version = object.ipcInt("version") ?? ipcProtocolVersion
        command = object.ipcString("command")
        source = object.ipcString("source")
        replyFormat = object.ipcString("reply_format")
        client = object.ipcString("client")
        clientVersion = object.ipcString("client_version")
        origin = object.ipcString("origin")
        cwd = object.ipcString("cwd")
        argv = object["argv"]?.arrayValue?.compactMap(\.stringValue)
        rawInput = object.ipcString("raw_input")
        files = object["files"]?.arrayValue?.compactMap(\.stringValue) ?? []
        for member in object["parameters"]?.objectValue ?? [:] {
            if let value = member.value.stringValue { setParameter(member.key, value) }
        }
        recipe = object.ipcString("recipe")
        json = object["json"]?.boolValue ?? false
        query = object.ipcString("query")
        async = object["async"]?.boolValue ?? false
        extra = JSONObject(object.members.filter { !Self.knownKeys.contains($0.key.lowercased()) })
    }

    /// The members that are set (empty lists and false flags left out), plus `extra`.
    public var jsonObject: JSONObject {
        var object: JSONObject = ["version": .number(Double(version))]
        func put(_ key: String, _ value: String?) {
            if let value { object[key] = .string(value) }
        }
        put("command", command)
        put("source", source)
        put("reply_format", replyFormat)
        put("client", client)
        put("client_version", clientVersion)
        put("origin", origin)
        put("cwd", cwd)
        if let argv { object["argv"] = .array(argv.map(JSONValue.string)) }
        put("raw_input", rawInput)
        if !files.isEmpty { object["files"] = .array(files.map(JSONValue.string)) }
        if !parameters.isEmpty {
            object["parameters"] = .object(JSONObject(parameters.keys.sorted().map { JSONMember($0, .string(parameters[$0] ?? "")) }))
        }
        put("recipe", recipe)
        if json { object["json"] = .bool(true) }
        put("query", query)
        if async { object["async"] = .bool(true) }
        for member in extra where !object.contains(key: member.key) {
            object[member.key] = member.value
        }
        return object
    }
}

/// Where a streamed chunk goes.
public enum IPCStream: String, Sendable {
    case stdout, stderr
}

/// A handler's final reply (upstream's anonymous `{ status, exit_code, stdout, stderr }` objects).
public struct IPCReply: Equatable, Sendable {
    public var status: String
    public var exitCode: Int32
    public var stdout: String?
    public var stderr: String?
    /// More members, e.g. `version` or `watching`.
    public var extra: JSONObject

    public init(status: String, exitCode: Int32, stdout: String? = nil, stderr: String? = nil, extra: JSONObject = [:]) {
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.extra = extra
    }

    public static func ok(_ stdout: String? = nil, extra: JSONObject = [:]) -> IPCReply {
        IPCReply(status: "ok", exitCode: IPCExitCode.ok, stdout: stdout, extra: extra)
    }

    public static func error(_ stderr: String, exitCode: Int32 = IPCExitCode.failure) -> IPCReply {
        IPCReply(status: "error", exitCode: exitCode, stderr: stderr)
    }

    public var isError: Bool { status.caseInsensitiveCompare("error") == .orderedSame }

    public var jsonObject: JSONObject {
        var object: JSONObject = ["status": .string(status), "exit_code": .number(Double(exitCode))]
        if let stdout { object["stdout"] = .string(stdout) }
        if let stderr { object["stderr"] = .string(stderr) }
        for member in extra where !object.contains(key: member.key) {
            object[member.key] = member.value
        }
        return object
    }

    /// A final reply read back from JSON; nil for a streamed chunk or an event.
    public init?(json object: JSONObject) {
        guard let status = object.ipcString("status") else { return nil }
        self.status = status
        exitCode = Int32(clamping: object.ipcInt("exit_code") ?? 0)
        stdout = object.ipcString("stdout")
        stderr = object.ipcString("stderr")
        extra = JSONObject(object.members.filter { !["status", "exit_code", "stdout", "stderr"].contains($0.key) })
    }
}

/// The modes of the Mac's CAPTURE command and `greenshotmac://capture/<mode>` links.
public enum AutomationCaptureMode: String, CaseIterable, Sendable {
    case region, window, fullScreen = "fullscreen", lastRegion = "last", text

    /// The mode's name and its aliases, any case.
    public init?(name: String?) {
        guard let name else { return nil }
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
        switch key {
        case "region", "area": self = .region
        case "window": self = .window
        case "fullscreen", "screen": self = .fullScreen
        case "last", "lastregion": self = .lastRegion
        case "text", "ocr": self = .text
        default: return nil
        }
    }

    public static let namesForHelp = "region, window, fullscreen, last or text"
}

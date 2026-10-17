// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The outcome of parsing a command line (upstream `CliParseResult`).
public struct IPCParseResult: Equatable, Sendable {
    /// The command to dispatch; nil when parsing failed.
    public var envelope: IPCEnvelope?
    /// The message for stderr when parsing failed.
    public var error: String?
    /// `--json` was given (also for errors, so they are reported as JSON).
    public var json: Bool

    public static func ok(_ envelope: IPCEnvelope) -> IPCParseResult {
        IPCParseResult(envelope: envelope, error: nil, json: envelope.json)
    }

    public static func fail(_ detail: String, json: Bool, usageHint: Bool = true) -> IPCParseResult {
        IPCParseResult(envelope: nil, error: "Error: " + detail + (usageHint ? "\nUse 'greenshot-cli --help' for usage." : ""), json: json)
    }

    public var isSuccess: Bool { envelope != nil }
}

/// The command line syntax of greenshot-cli, also used for the command after the startup options of the app itself
/// (upstream `Ipc/Cli/CliCommandParser.cs`). greenshot-cli sends the arguments unparsed; the app parses them here, for
/// the source of the connection.
public enum IPCCommandLine {
    /// One option of greenshot-cli: its spellings, its line in the help and how it turns the arguments into a command.
    public struct Verb: Sendable {
        public var flags: [String]
        /// The left column of the help, e.g. "--file, -f <file...>".
        public var synopsis: String
        public var help: String
        /// Shown in the help.
        public var listed: Bool
        /// The arguments (the flag first), the working directory and whether `--json` was given.
        public var parse: @Sendable (_ argv: [String], _ cwd: String?, _ json: Bool) -> IPCParseResult

        public init(flags: [String], synopsis: String, help: String, listed: Bool = true,
                    parse: @escaping @Sendable ([String], String?, Bool) -> IPCParseResult) {
            self.flags = flags
            self.synopsis = synopsis
            self.help = help
            self.listed = listed
            self.parse = parse
        }

        func matches(_ argument: String) -> Bool {
            flags.contains { $0.caseInsensitiveCompare(argument) == .orderedSame }
        }
    }

    /// The answer of the recipe commands while the app has no recipe runtime (it is still starting, or a test).
    public static let recipesUnavailable = "Error: recipes are not available yet in Greenshot for Mac."

    public static let verbs: [Verb] = [
        Verb(flags: ["--file", "-f"], synopsis: "--file, -f <file...>", help: "Open one or more image files in the editor") { argv, cwd, json in
            guard argv.count >= 2 else { return .fail("missing file argument after '\(argv[0])'.", json: json) }
            var envelope = make(IPCCommand.openFile, cwd: cwd)
            envelope.files = Array(argv.dropFirst())
            return .ok(envelope)
        },
        Verb(flags: ["--capture", "-c"], synopsis: "--capture, -c <mode>",
             help: "Take a screenshot: \(AutomationCaptureMode.namesForHelp)") { argv, cwd, json in
            guard argv.count >= 2 else { return .fail("missing capture mode after '\(argv[0])'.", json: json) }
            guard let mode = AutomationCaptureMode(name: argv[1]) else {
                return .fail("unknown capture mode '\(argv[1])'. Use \(AutomationCaptureMode.namesForHelp).", json: json)
            }
            if argv.count > 2 { return .fail("unexpected argument '\(argv[2])'.", json: json) }
            var envelope = make(IPCCommand.capture, cwd: cwd)
            envelope.setParameter("mode", mode.rawValue)
            return .ok(envelope)
        },
        single(["--reload"], help: "Reload the settings of the running app", command: IPCCommand.reloadConfig),
        single(["--exit"], help: "Quit the running app", command: IPCCommand.exit),
        single(["--version", "-v"], help: "Show the version", command: IPCCommand.version),
        // Upstream's recipe options (CliCommandParser.ParseCommandLine)
        Verb(flags: ["--recipe", "-r"], synopsis: "--recipe, -r <cmd|id> [arguments]",
             help: "Run a recipe: key=value or --key value; --json, --query <expr>, --async") { argv, cwd, json in
            parseRunRecipe(argv, cwd: cwd, json: json)
        },
        Verb(flags: ["--list-recipes", "-l"], synopsis: "--list-recipes, -l [--json]",
             help: "List the recipes of the command line") { argv, cwd, _ in
            parseJSONFlagOnly(argv, from: 1, envelope: make(IPCCommand.listRecipes, cwd: cwd))
        },
        Verb(flags: ["--info", "-i"], synopsis: "--info, -i <recipe> [--json]",
             help: "Describe a recipe: its arguments, steps and warnings") { argv, cwd, json in
            guard argv.count >= 2 else { return .fail("missing recipe identifier after '\(argv[0])'.", json: json) }
            var envelope = make(IPCCommand.describeRecipe, cwd: cwd)
            envelope.recipe = argv[1]
            return parseJSONFlagOnly(argv, from: 2, envelope: envelope)
        },
    ]

    /// Upstream `ParseJsonFlagOnly`: only a trailing `--json` (for `--list-recipes` and `--info`).
    private static func parseJSONFlagOnly(_ argv: [String], from first: Int, envelope: IPCEnvelope) -> IPCParseResult {
        var envelope = envelope
        for index in first..<max(first, argv.count) {
            if argv[index].caseInsensitiveCompare("--json") == .orderedSame {
                envelope.json = true
            } else {
                let json = envelope.json || argv[index...].contains { $0.caseInsensitiveCompare("--json") == .orderedSame }
                return .fail("unexpected argument '\(argv[index])'.", json: json)
            }
        }
        return .ok(envelope)
    }

    /// Upstream `ParseRunRecipe`: `--recipe <id>` and the recipe's arguments (`key=value`, `--key=value`, `--key value`,
    /// `-k value`; values are taken as they are, also when they start with `-`), and the options `--json`, `--query`/`-q`
    /// (`--query=`), `--async` and `--`, after which everything is an argument.
    static func parseRunRecipe(_ argv: [String], cwd: String?, json: Bool) -> IPCParseResult {
        guard argv.count >= 2 else { return .fail("missing recipe identifier after '\(argv[0])'.", json: json) }
        var envelope = make(IPCCommand.runRecipe, cwd: cwd)
        envelope.recipe = argv[1]
        var optionsEnded = false
        var index = 2
        while index < argv.count {
            let argument = argv[index]
            if !optionsEnded {
                if argument == "--" {
                    optionsEnded = true
                    index += 1
                    continue
                }
                if argument.caseInsensitiveCompare("--json") == .orderedSame {
                    envelope.json = true
                    index += 1
                    continue
                }
                if argument.caseInsensitiveCompare("--async") == .orderedSame {
                    envelope.async = true
                    index += 1
                    continue
                }
                if argument.caseInsensitiveCompare("--query") == .orderedSame || argument.caseInsensitiveCompare("-q") == .orderedSame {
                    guard index + 1 < argv.count else { return .fail("'\(argument)' requires an expression.", json: json) }
                    envelope.query = argv[index + 1]
                    index += 2
                    continue
                }
                if argument.lowercased().hasPrefix("--query=") {
                    envelope.query = String(argument.dropFirst("--query=".count))
                    index += 1
                    continue
                }
                if argument.hasPrefix("-") {
                    // --key=value, --key value (also -k value)
                    let name = argument.hasPrefix("--") ? String(argument.dropFirst(2)) : String(argument.dropFirst())
                    let equals = name.firstIndex(of: "=")
                    let key = equals.map { String(name[..<$0]) } ?? name
                    guard !key.isEmpty else { return .fail("invalid argument '\(argument)'.", json: json) }
                    if let equals {
                        envelope.setParameter(key, String(name[name.index(after: equals)...]))
                        index += 1
                    } else {
                        guard index + 1 < argv.count else { return .fail("missing value for argument '\(argument)'.", json: json) }
                        envelope.setParameter(key, argv[index + 1])
                        index += 2
                    }
                    continue
                }
            }
            // key=value
            guard let separator = argument.firstIndex(of: "="), separator != argument.startIndex else {
                return .fail("unexpected argument '\(argument)'. Pass recipe arguments as key=value, --key=value or --key value.",
                             json: json)
            }
            envelope.setParameter(String(argument[..<separator]), String(argument[argument.index(after: separator)...]))
            index += 1
        }
        return .ok(envelope)
    }

    /// An option without arguments.
    private static func single(_ flags: [String], help: String, command: String) -> Verb {
        Verb(flags: flags, synopsis: flags.joined(separator: ", "), help: help) { argv, cwd, json in
            if argv.count > 1 { return .fail("unexpected argument '\(argv[1])'.", json: json) }
            return .ok(make(command, cwd: cwd))
        }
    }

    private static func make(_ command: String, cwd: String?) -> IPCEnvelope {
        var envelope = IPCEnvelope(command: command)
        envelope.cwd = cwd
        return envelope
    }

    /// Parses a forwarded command line for its source: `cli` the full syntax, `url_scheme` exactly one link, `open_with`
    /// file paths (optionally after `--file`). The command still has to pass the whitelist of the source.
    public static func parse(_ argv: [String], source: IPCSource, cwd: String?) -> IPCParseResult {
        switch source {
        case .cli:
            return parseCommandLine(argv, cwd: cwd)
        case .urlScheme:
            guard argv.count == 1, URLActionParser.isActionLink(argv[0]) else {
                return .fail("expected exactly one greenshotmac: link.", json: false, usageHint: false)
            }
            var envelope = make(IPCCommand.urlScheme, cwd: cwd)
            envelope.rawInput = argv[0]
            return .ok(envelope)
        case .openWith:
            let startsWithFlag = argv.first.map { $0.caseInsensitiveCompare("--file") == .orderedSame || $0 == "-f" } ?? false
            let first = startsWithFlag ? 1 : 0
            guard argv.count > first else { return .fail("no file to open.", json: false, usageHint: false) }
            var envelope = make(IPCCommand.openFile, cwd: cwd)
            envelope.files = Array(argv.dropFirst(first))
            return .ok(envelope)
        default:
            return .fail("command lines are not accepted from source '\(source.rawValue)'.", json: false, usageHint: false)
        }
    }

    private static func parseCommandLine(_ argv: [String], cwd: String?) -> IPCParseResult {
        let json = argv.contains { $0.caseInsensitiveCompare("--json") == .orderedSame }
        guard let first = argv.first else { return .fail("no command given.", json: json) }
        if let verb = verbs.first(where: { $0.matches(first) }) {
            return verb.parse(argv, cwd, json)
        }
        if URLActionParser.isActionLink(first) {
            if argv.count > 1 { return .fail("unexpected argument '\(argv[1])' after the link.", json: json) }
            var envelope = make(IPCCommand.urlScheme, cwd: cwd)
            envelope.rawInput = first
            return .ok(envelope)
        }
        if first.hasPrefix("-") { return .fail("unrecognized option '\(first)'.", json: json) }
        // Default: file paths
        var envelope = make(IPCCommand.openFile, cwd: cwd)
        envelope.files = argv
        return .ok(envelope)
    }

    // MARK: Help

    /// greenshot-cli's help (upstream `main_cli.c` `Usage`), from the verbs; `installedPath` is the tool's own path for
    /// the line that puts it on the PATH.
    public static func cliUsage(installedPath: String?) -> String {
        let listed = verbs.filter(\.listed)
        let rows = listed.map { ($0.synopsis, $0.help) } + [
            ("--help, -h", "Show this help text"),
            ("greenshotmac://<link>", "Run a link, e.g. greenshotmac://settings?tab=editor"),
        ]
        let width = (rows.map(\.0.count).max() ?? 0) + 3
        let options = rows.map { "  " + $0.0.padding(toLength: width, withPad: " ", startingAt: 0) + $0.1 }.joined(separator: "\n")
        var text = """
            Greenshot for Mac (Community) command line

            Usage:
              greenshot-cli [options]
              greenshot-cli <file...>

            Options:
            \(options)

            The running app does the work; when it isn't running, greenshot-cli starts it.
            Screenshots of the full screen, a window or the last region ask you to allow them first.

            Exit codes:
              0 success, 1 failure, 2 invalid command line, 3 Greenshot for Mac not available.

            """
        if let installedPath {
            text += """

                Put it on your PATH:
                  sudo ln -sf '\(installedPath)' /usr/local/bin/greenshot-cli

                """
        }
        return text
    }

    // MARK: The app's own command line

    /// The app's startup options and the command after them (upstream `Helpers/GreenshotCommandLine.cs`).
    public struct StartupOptions: Equatable, Sendable {
        public var help = false
        /// Started by greenshot-cli or a script: no "is running" message, and end silently when the app runs already
        /// (the Mac's counterpart of upstream's `--autostart`).
        public var background = false
        public var snapshot = false
        /// `--diagnostics-test <test> [path]` of debug builds (`CrashReporting.runDebugTest`): like `--snapshot`, a
        /// development run that skips the single-instance guard.
        public var diagnostics = false
        /// `--language <code>`: the language of the app's texts, kept in the settings (upstream `--language`).
        public var language: String?
        /// The arguments after the startup options: a command in greenshot-cli's syntax; empty when there is none.
        public var command: [String] = []

        public init() {}
    }

    /// Startup options with a value.
    private static let optionsWithValue = ["--settings-dir", "--snapshot", "--language"]
    private static let flags = ["--background", "--help", "-h", "-?"]

    /// Splits the arguments (without the program path) into startup options and the command. Also skipped: the process
    /// serial number LaunchServices added in old macOS versions (`-psn_…`) and user-defaults arguments like
    /// `-NSDocumentRevisionsDebugMode YES` or `-AppleLanguages (de)` (one dash, a capital letter, a value).
    public static func scanStartup(_ arguments: [String]) -> StartupOptions {
        var options = StartupOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let lowered = argument.lowercased()
            if optionsWithValue.contains(lowered) {
                if lowered == "--snapshot" { options.snapshot = true }
                if lowered == "--language", index + 1 < arguments.count { options.language = arguments[index + 1] }
                index = min(index + 2, arguments.count)
            } else if optionsWithValue.contains(where: { lowered.hasPrefix($0 + "=") }) {
                if lowered.hasPrefix("--snapshot=") { options.snapshot = true }
                if lowered.hasPrefix("--language=") { options.language = String(argument.dropFirst("--language=".count)) }
                index += 1
            } else if lowered == "--diagnostics-test" {
                // A test name, and for `signature` an optional path
                options.diagnostics = true
                let test = index + 1 < arguments.count ? arguments[index + 1].lowercased() : ""
                index = min(index + 2, arguments.count)
                if test == "signature", index < arguments.count, !arguments[index].hasPrefix("-") { index += 1 }
            } else if flags.contains(lowered) {
                if lowered == "--background" { options.background = true } else { options.help = true }
                index += 1
            } else if argument.hasPrefix("-psn_") {
                index += 1
            } else if isDefaultsArgument(argument) {
                index = min(index + 2, arguments.count)
            } else {
                break
            }
        }
        options.command = Array(arguments[index...])
        return options
    }

    private static func isDefaultsArgument(_ argument: String) -> Bool {
        let scalars = Array(argument.unicodeScalars)
        guard scalars.count > 1, scalars[0] == "-" else { return false }
        return CharacterSet.uppercaseLetters.contains(scalars[1])
    }

    /// The app's help (upstream `GreenshotCommandLine.BuildRootCommand`).
    public static let appUsage = """
        Greenshot for Mac (Community) - an unofficial macOS port of Greenshot

        Usage: GreenshotMac [startup options] [command]

        Startup options:
          --settings-dir <folder>   Keep the settings in <folder>/settings.json instead of the user defaults
          --language <code>         Use this language for the texts and keep it (e.g. de-DE; system = as macOS)
          --background              Start without the "is running" message; end silently when the app runs already
          --snapshot <folder>       Render the windows to PNG files and quit (for development)
          --help, -h, -?            Show this help text

        The command has the same syntax as for greenshot-cli (see greenshot-cli --help), e.g.
          GreenshotMac image.png            open a file in the editor
          GreenshotMac --reload / --exit    reload the settings / quit the app
        The command is sent to the running app; if none is running, the app starts and runs it.
        Unlike greenshot-cli, GreenshotMac shows no output of the command.

        """
}

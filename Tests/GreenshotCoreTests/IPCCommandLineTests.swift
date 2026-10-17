// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `CliProtocolTests`.
struct IPCCommandLineTests {
    private func command(_ argv: [String]) -> String? {
        IPCCommandLine.parse(argv, source: .cli, cwd: "/tmp").envelope?.command
    }

    private func error(_ argv: [String]) -> String {
        IPCCommandLine.parse(argv, source: .cli, cwd: "/tmp").error ?? ""
    }

    @Test(arguments: [
        ("OPEN_FILE", ["--file", "a.png", "b.png"]),
        ("OPEN_FILE", ["-f", "a.png"]),
        ("OPEN_FILE", ["a.png"]),
        ("RELOAD_CONFIG", ["--reload"]),
        ("EXIT", ["--exit"]),
        ("EXIT", ["--EXIT"]),
        ("VERSION", ["--version"]),
        ("VERSION", ["-v"]),
        ("URL_SCHEME", ["greenshotmac://settings"]),
        ("URL_SCHEME", ["greenshot://settings"]),
        ("URL_SCHEME", ["greenshotmac:about"]),
        ("CAPTURE", ["--capture", "fullscreen"]),
        ("CAPTURE", ["-c", "region"]),
        ("RUN_RECIPE", ["--recipe", "ocr", "destination=clipboard"]),
        ("LIST_RECIPES", ["--list-recipes"]),
        ("DESCRIBE_RECIPE", ["--info", "qr"]),
    ])
    func commandsMapToDispatcherCommands(expected: String, argv: [String]) {
        #expect(command(argv) == expected)
    }

    @Test(arguments: [
        ("unexpected argument 'now'", ["--reload", "now"]),
        ("unrecognized option '--unknown'", ["--unknown"]),
        ("missing file argument after '--file'", ["--file"]),
        ("missing capture mode after '--capture'", ["--capture"]),
        ("unknown capture mode 'movie'", ["--capture", "movie"]),
        ("unexpected argument 'extra'", ["--capture", "window", "extra"]),
        ("missing recipe identifier", ["--recipe"]),
        ("unexpected argument 'x' after the link", ["greenshotmac://about", "x"]),
        ("no command given", []),
    ])
    func invalidCommandLinesReportUsageErrors(expected: String, argv: [String]) {
        let message = error(argv)
        #expect(message.contains(expected))
        #expect(message.hasPrefix("Error: "))
        #expect(message.contains("greenshot-cli --help"))
    }

    @Test func filesKeepTheirOrderAndTheCallersFolder() throws {
        let envelope = try #require(IPCCommandLine.parse(["--file", "b.png", "a b.png"], source: .cli, cwd: "/Users/me").envelope)
        #expect(envelope.files == ["b.png", "a b.png"])
        #expect(envelope.cwd == "/Users/me")
    }

    @Test func captureModeIsNormalized() throws {
        let envelope = try #require(IPCCommandLine.parse(["--capture", "Full-Screen"], source: .cli, cwd: nil).envelope)
        #expect(envelope.parameter("mode") == "fullscreen")
    }

    @Test func linkIsKeptRaw() throws {
        let envelope = try #require(IPCCommandLine.parse(["greenshotmac://log?search=HDR"], source: .cli, cwd: nil).envelope)
        #expect(envelope.rawInput == "greenshotmac://log?search=HDR")
    }

    @Test func invalidCommandLineWithJsonIsReportedAsJson() {
        let result = IPCCommandLine.parse(["--bogus", "--json"], source: .cli, cwd: nil)
        #expect(result.json)
        #expect(!result.isSuccess)
    }

    @Test func urlSchemeSourceAcceptsOnlyASingleLink() {
        #expect(IPCCommandLine.parse(["greenshotmac://about"], source: .urlScheme, cwd: nil).envelope?.command == "URL_SCHEME")
        #expect(!IPCCommandLine.parse(["--exit"], source: .urlScheme, cwd: nil).isSuccess)
        #expect(!IPCCommandLine.parse(["greenshotmac://about", "x"], source: .urlScheme, cwd: nil).isSuccess)
        #expect(!IPCCommandLine.parse([], source: .urlScheme, cwd: nil).isSuccess)
    }

    @Test func openWithSourceAcceptsOnlyFiles() {
        let plain = IPCCommandLine.parse(["a.png"], source: .openWith, cwd: nil).envelope
        #expect(plain?.command == "OPEN_FILE")
        #expect(plain?.files == ["a.png"])
        let flagged = IPCCommandLine.parse(["--file", "a.png"], source: .openWith, cwd: nil).envelope
        #expect(flagged?.files == ["a.png"])
        #expect(!IPCCommandLine.parse(["--file"], source: .openWith, cwd: nil).isSuccess)
    }

    @Test func otherSourcesAreRejected() {
        #expect(!IPCCommandLine.parse(["--exit"], source: .nativeMessaging, cwd: nil).isSuccess)
        #expect(!IPCCommandLine.parse(["--exit"], source: .appleScript, cwd: nil).isSuccess)
    }

    @Test func helpListsTheOptionsAndThePathStep() {
        let usage = IPCCommandLine.cliUsage(installedPath: "/Applications/X.app/Contents/Helpers/greenshot-cli")
        for verb in IPCCommandLine.verbs where verb.listed {
            #expect(usage.contains(verb.synopsis))
        }
        #expect(usage.contains("Exit codes"))
        #expect(usage.contains("/usr/local/bin/greenshot-cli"))
        #expect(usage.contains("--recipe, -r <cmd|id> [arguments]"))
        #expect(usage.contains("--list-recipes, -l [--json]"))
        #expect(usage.contains("--info, -i <recipe> [--json]"))
        #expect(!IPCCommandLine.cliUsage(installedPath: nil).contains("/usr/local/bin"))
    }

    @Test func startsAppExceptForExitAndReload() {
        #expect(IPCClient.startsApp(for: ["a.png"]))
        #expect(IPCClient.startsApp(for: []))
        #expect(!IPCClient.startsApp(for: ["--exit"]))
        #expect(!IPCClient.startsApp(for: ["--Reload"]))
    }
}

/// Upstream `GreenshotCommandLine`.
struct AppStartupOptionsTests {
    @Test func startupOptionsComeFirstThenTheCommand() {
        let options = IPCCommandLine.scanStartup(["--settings-dir", "/tmp/gs", "--exit"])
        #expect(options.command == ["--exit"])
        #expect(!options.help)
        let joined = IPCCommandLine.scanStartup(["--settings-dir=/tmp/gs", "a.png", "--settings-dir"])
        #expect(joined.command == ["a.png", "--settings-dir"])
    }

    @Test func helpAndBackground() {
        #expect(IPCCommandLine.scanStartup(["--help"]).help)
        #expect(IPCCommandLine.scanStartup(["-h"]).help)
        #expect(IPCCommandLine.scanStartup(["-?"]).help)
        let background = IPCCommandLine.scanStartup(["--background"])
        #expect(background.background)
        #expect(background.command.isEmpty)
    }

    @Test func snapshotIsAStartupOption() {
        let options = IPCCommandLine.scanStartup(["--snapshot", "/tmp/snaps"])
        #expect(options.snapshot)
        #expect(options.command.isEmpty)
    }

    @Test func diagnosticsTestIsAStartupOption() {
        let crash = IPCCommandLine.scanStartup(["--diagnostics-test", "crash"])
        #expect(crash.command.isEmpty)
        #expect(crash.diagnostics)
        #expect(IPCCommandLine.scanStartup(["--diagnostics-test", "check"]).command.isEmpty)
        #expect(IPCCommandLine.scanStartup(["--diagnostics-test", "signature", "/Applications/X.app"]).command.isEmpty)
        #expect(IPCCommandLine.scanStartup(["--diagnostics-test", "signature"]).command.isEmpty)
        #expect(IPCCommandLine.scanStartup(["--diagnostics-test", "signature", "--reload"]).command == ["--reload"])
        #expect(IPCCommandLine.scanStartup(["--diagnostics-test", "crash", "a.png"]).command == ["a.png"])
    }

    @Test func systemArgumentsAreSkipped() {
        let options = IPCCommandLine.scanStartup(["-psn_0_12345", "-NSDocumentRevisionsDebugMode", "YES",
                                                  "-AppleLanguages", "(de)", "--reload"])
        #expect(options.command == ["--reload"])
    }

    @Test func lowercaseShortOptionsStartTheCommand() {
        #expect(IPCCommandLine.scanStartup(["-f", "a.png"]).command == ["-f", "a.png"])
        #expect(IPCCommandLine.scanStartup([]).command.isEmpty)
    }
}

/// Upstream `SecurityDispatcher_UrlScheme_*`.
struct URLActionParserTests {
    private func command(_ link: String) -> String? {
        if case .command(let name, _) = URLActionParser.parse(link) { return name }
        return nil
    }

    private func parameter(_ link: String, _ name: String) -> String? {
        guard case .command(_, let parameters) = URLActionParser.parse(link) else { return nil }
        return parameters.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    @Test(arguments: [
        ("greenshotmac:settings", "SETTINGS"),
        ("greenshotmac:settings?tab=capture", "SETTINGS"),
        ("greenshotmac://settings?tab=general", "SETTINGS"),
        ("GreenshotMac://Settings/", "SETTINGS"),
        ("greenshot:about", "ABOUT"),
        ("greenshot://about", "ABOUT"),
        ("greenshotmac:self-service?section=debug", "SELF_SERVICE"),
        ("greenshotmac://log?search=HDR%20tone", "LOG_VIEWER"),
        ("greenshotmac://recipe-editor?recipe=ocr", "RECIPE_EDITOR"),
        ("greenshotmac://recipe-manager", "RECIPE_MANAGER"),
        ("greenshotmac:recipe/my-task?destination=clipboard", "RUN_RECIPE"),
        ("greenshotmac://capture/region", "CAPTURE"),
        ("greenshotmac://capture?mode=window", "CAPTURE"),
        ("greenshotmac://clipboard", "OPEN_CLIPBOARD"),
        ("greenshotmac://exit", "EXIT"),
        ("greenshotmac:reload_config", "RELOAD_CONFIG"),
        ("greenshotmac://first_launch", "FIRST_LAUNCH"),
        ("greenshotmac://open_file?path=/tmp/a.png", "OPEN_FILE"),
    ])
    func linksNameTheirCommand(link: String, expected: String) {
        #expect(command(link) == expected)
    }

    @Test func parametersAreDecoded() {
        #expect(parameter("greenshotmac://settings?tab=capture", "tab") == "capture")
        #expect(parameter("greenshotmac://log?search=HDR%20tone", "search") == "HDR tone")
        #expect(parameter("greenshotmac://log?search=a+b", "search") == "a+b")
        #expect(parameter("greenshotmac://self-service?section=debug", "section") == "debug")
        #expect(parameter("greenshotmac://recipe-editor?recipe=ocr", "recipe") == "ocr")
        #expect(parameter("greenshotmac:recipe/my-task?destination=clipboard", "recipe") == "my-task")
        #expect(parameter("greenshotmac:recipe/my-task?destination=clipboard", "destination") == "clipboard")
        #expect(parameter("greenshotmac://capture/fullscreen", "mode") == "fullscreen")
        #expect(parameter("greenshotmac://settings?tab=a&TAB=b", "tab") == "b")
        #expect(parameter("greenshotmac://settings?flag", "flag") == "")
    }

    @Test func commandsCarryingTheLinkLeadNowhere() {
        #expect(URLActionParser.parse("greenshotmac://cli") == .invalid)
        #expect(URLActionParser.parse("greenshotmac:url_scheme") == .invalid)
        #expect(URLActionParser.parse("greenshotmac://") == .invalid)
        #expect(URLActionParser.parse("https://example.com") == .invalid)
    }

    @Test func signInCallbacksAreIgnored() {
        #expect(URLActionParser.parse("greenshotmac://oauth/dropbox?code=abc") == .ignored)
        #expect(URLActionParser.parse("greenshotmac://oauth") == .ignored)
    }

    @Test func actionLinksAreRecognized() {
        #expect(URLActionParser.isActionLink("greenshotmac://about"))
        #expect(URLActionParser.isActionLink("GREENSHOT:about"))
        #expect(!URLActionParser.isActionLink("greenshots://about"))
        #expect(!URLActionParser.isActionLink("a.png"))
    }
}

/// Upstream `HandleSettingsAsync` / `ShowSetting(plugin, tab)`.
struct AutomationLinksTests {
    @Test func settingsTabsAndPlugins() {
        #expect(AutomationLinks.settingsPane(tab: "editor", plugin: nil) == .editor)
        #expect(AutomationLinks.settingsPane(tab: "destination", plugin: nil) == .destinations)
        #expect(AutomationLinks.settingsPane(tab: "plugins", plugin: nil) == .destinations)
        #expect(AutomationLinks.settingsPane(tab: "Jira", plugin: nil) == .destinations)
        #expect(AutomationLinks.settingsPane(tab: nil, plugin: "Box") == .destinations)
        #expect(AutomationLinks.settingsPane(tab: "general", plugin: "Dropbox") == .destinations)
        #expect(AutomationLinks.settingsPane(tab: "video", plugin: nil) == .video)
        #expect(AutomationLinks.settingsPane(tab: nil, plugin: "RecipeEditor") == .recipes)
        #expect(AutomationLinks.settingsPane(tab: "recipeeditor", plugin: nil) == .recipes)
        #expect(AutomationLinks.settingsPane(tab: "aitools", plugin: nil) == .aiTools)
    }

    @Test func noOrUnknownTabKeepsTheLastOne() {
        #expect(AutomationLinks.settingsPane(tab: nil, plugin: nil) == nil)
        #expect(AutomationLinks.settingsPane(tab: "recipes", plugin: nil) == .recipes)
        #expect(AutomationLinks.settingsPane(tab: "nonsense", plugin: " ") == nil)
    }
}

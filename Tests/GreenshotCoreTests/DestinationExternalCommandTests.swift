// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct DestinationExternalCommandTests {
    @Test func commandsSavedBeforeTheFormatStillLoad() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Upload","command":"/usr/local/bin/up","arguments":"\"{0}\"","runInBackground":false,"copyURLFromOutput":true,"copyOutputToClipboard":true}"#
        let command = try JSONDecoder().decode(ExternalCommand.self, from: Data(json.utf8))
        #expect(command.id == id && command.name == "Upload" && command.command == "/usr/local/bin/up")
        #expect(!command.runInBackground && command.copyOutputToClipboard && command.format == .png)
        var jpeg = command
        jpeg.format = .jpg
        #expect(try JSONDecoder().decode(ExternalCommand.self, from: JSONEncoder().encode(jpeg)) == jpeg)
    }

    /// DST-074: "Write the output to the log" (upstream `ShowStandardOutputInLog`) is off for commands saved before it.
    @Test func outputInTheLogIsOffForOldCommandsAndKept() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Upload","command":"/usr/local/bin/up","arguments":"\"{0}\"","format":"png"}"#
        let old = try JSONDecoder().decode(ExternalCommand.self, from: Data(json.utf8))
        #expect(!old.showOutputInLog)
        var logging = old
        logging.showOutputInLog = true
        let decoded = try JSONDecoder().decode(ExternalCommand.self, from: JSONEncoder().encode(logging))
        #expect(decoded.showOutputInLog)
        #expect(decoded == logging)
        let made = ExternalCommand(name: "Echo", command: "/bin/echo", showOutputInLog: true)
        #expect(made.showOutputInLog)
        #expect(!ExternalCommand(name: "Echo", command: "/bin/echo").showOutputInLog)
    }

    @Test func settingsWithOldCommandsKeepThem() throws {
        let json = #"{"externalCommands":[{"id":"\#(UUID().uuidString)","name":"Mine","command":"/bin/echo","arguments":"{0}","runInBackground":true,"copyURLFromOutput":false,"copyOutputToClipboard":false}]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.externalCommands.map(\.name) == ["Mine"])
    }

    @Test func variablesAreFilledPerArgument() {
        let context = FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: "My Window",
                                              environment: ["HOME": "/Users/me"], timeZone: TimeZone(identifier: "UTC")!)
        let fill: (String) -> String = { FilenamePattern.fill($0, context: context, filenameSafe: false) }
        // A title with a space stays one argument, like the file.
        #expect(ExternalCommandLine.arguments("--title ${title} \"{0}\" ${YYYY}", file: "/tmp/a b.png", fill: fill)
                == ["--title", "My Window", "/tmp/a b.png", "1970"])
        #expect(ExternalCommandLine.program("${HOME}/bin/up", fill: fill) == .executable("/Users/me/bin/up"))
        // An empty argument stays empty (it was "greenshot <time>"), and an empty command is none.
        #expect(ExternalCommandLine.arguments("a \"\" b", file: "/tmp/a.png", fill: fill) == ["a", "", "b"])
        #expect(ExternalCommandLine.program(" ", fill: fill) == nil)
    }

    @Test func programKinds() {
        #expect(ExternalCommandLine.program("/Applications/Preview.app") == .application("/Applications/Preview.app"))
        #expect(ExternalCommandLine.program("/usr/bin/open") == .executable("/usr/bin/open"))
        #expect(ExternalCommandLine.program("convert") == .searchPath("convert"))
        #expect(ExternalCommandLine.program("  ") == nil)
        #expect(ExternalCommandLine.program("~/bin/x") == .executable(NSHomeDirectory() + "/bin/x"))
    }

    @Test func availability() {
        let files: Set<String> = ["/Applications/Preview.app", "/usr/bin/open", "/opt/homebrew/bin/convert"]
        func available(_ program: ExternalCommandLine.Program) -> Bool {
            ExternalCommandLine.isAvailable(program, fileExists: files.contains, isExecutable: files.contains,
                                            searchPath: ["/usr/bin", "/opt/homebrew/bin"])
        }
        #expect(available(.application("/Applications/Preview.app")))
        #expect(!available(.application("/Applications/Gone.app")))
        #expect(available(.executable("/usr/bin/open")) && !available(.executable("/usr/bin/gone")))
        #expect(available(.searchPath("convert")) && !available(.searchPath("missing")))
    }

    @Test func applicationNameForTheIcon() {
        #expect(ExternalCommandLine.applicationName(inArguments: "-a Preview \"{0}\"") == "Preview")
        #expect(ExternalCommandLine.applicationName(inArguments: "-a \"Pixelmator Pro\" \"{0}\"") == "Pixelmator Pro")
        #expect(ExternalCommandLine.applicationName(inArguments: "\"{0}\"") == nil)
        #expect(ExternalCommandLine.applicationName(inArguments: "-a") == nil)
    }

    @Test func duplicateNames() {
        let first = ExternalCommand(name: "Preview", command: "/usr/bin/open")
        let second = ExternalCommand(name: "Upload", command: "/bin/up")
        #expect(ExternalCommandLine.isDuplicate(name: " preview ", of: nil, among: [first, second]))
        #expect(!ExternalCommandLine.isDuplicate(name: "Preview", of: first.id, among: [first, second]))
        #expect(ExternalCommandLine.isDuplicate(name: "UPLOAD", of: first.id, among: [first, second]))
        #expect(!ExternalCommandLine.isDuplicate(name: "", of: nil, among: [first]))
    }
}

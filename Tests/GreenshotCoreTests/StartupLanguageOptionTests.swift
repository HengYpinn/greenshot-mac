// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// `--language <code>` among the app's startup options (upstream `GreenshotCommandLine` LanguageOption).
struct StartupLanguageOptionTests {
    @Test func bothForms() {
        let separate = IPCCommandLine.scanStartup(["--language", "de-DE"])
        #expect(separate.language == "de-DE")
        #expect(separate.command.isEmpty)
        let joined = IPCCommandLine.scanStartup(["--language=fr-FR", "--exit"])
        #expect(joined.language == "fr-FR")
        #expect(joined.command == ["--exit"])
    }

    @Test func withOtherOptionsAndACommand() {
        let options = IPCCommandLine.scanStartup(["--settings-dir", "/tmp/gs", "--language", "ja-JP", "--background", "a.png"])
        #expect(options.language == "ja-JP")
        #expect(options.background)
        #expect(options.command == ["a.png"])
        let snapshot = IPCCommandLine.scanStartup(["--snapshot", "/tmp/s", "--language", "ar-SY"])
        #expect(snapshot.snapshot)
        #expect(snapshot.language == "ar-SY")
    }

    @Test func withoutAValue() {
        let options = IPCCommandLine.scanStartup(["--language"])
        #expect(options.language == nil)
        #expect(options.command.isEmpty)
        #expect(IPCCommandLine.scanStartup(["--exit"]).language == nil)
    }

    @Test func theHelpListsIt() {
        #expect(IPCCommandLine.appUsage.contains("--language <code>"))
    }
}

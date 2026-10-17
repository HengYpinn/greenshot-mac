// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct FilenameMetadataTests {
    private func context(title: String? = "Safari: Start", metadata: [String: String] = [:],
                         environment: [String: String] = [:]) -> FilenamePattern.Context {
        FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: title, environment: environment,
                                timeZone: TimeZone(identifier: "UTC")!, metadata: metadata)
    }

    @Test func windowTitleFallsBackToTheTitle() {
        #expect(FilenamePattern.fill("${windowtitle}", context: context()) == "Safari_ Start")
        #expect(FilenamePattern.fill("${windowtitle}", context: context(metadata: ["windowtitle": "a/b"])) == "a_b")
        #expect(FilenamePattern.fill("${windowtitle}", context: context(metadata: ["windowtitle": "a/b"]), filenameSafe: false) == "a/b")
    }

    @Test func metadataComesAfterTheEnvironment() {
        // Cleaned like ${title} (review S-M1): a captured value never adds folders
        #expect(FilenamePattern.fill("${url}", context: context(metadata: ["url": "https://x.org/<p>"])) == "https___x.org__p_")
        #expect(FilenamePattern.fill("${source}", context: context(metadata: ["source": "Window"], environment: ["source": "env"])) == "env")
        #expect(FilenamePattern.fill("${browser}", context: context()) == "")
    }

    @Test func helpListsEveryVariable() {
        for variable in FilenamePattern.builtInVariables {
            let listed = FilenamePattern.helpText.contains("${\(variable)}") || FilenamePattern.helpText.contains("${\(variable):")
            #expect(listed, "\(variable) is missing from the help")
        }
    }
}

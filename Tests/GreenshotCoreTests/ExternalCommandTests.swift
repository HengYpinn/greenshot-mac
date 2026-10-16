// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct ExternalCommandTests {
    @Test func splitsLikeAShell() {
        #expect(ExternalCommandLine.split("-a Preview \"{0}\"") == ["-a", "Preview", "{0}"])
        #expect(ExternalCommandLine.split("  one   'two three' \"four \\\"five\\\"\" six\\ seven") ==
                ["one", "two three", "four \"five\"", "six seven"])
        #expect(ExternalCommandLine.split("\"\" x") == ["", "x"])
        #expect(ExternalCommandLine.split("") == [])
    }

    @Test func replacesTheFileAfterSplitting() {
        let path = "/tmp/My Shot.png"
        #expect(ExternalCommandLine.arguments("-a Preview \"{0}\"", file: path) == ["-a", "Preview", path])
        // Unquoted, a path with spaces still stays one argument.
        #expect(ExternalCommandLine.arguments("--file={0} -v", file: path) == ["--file=" + path, "-v"])
    }

    @Test func findsTheFirstURLInTheOutput() {
        #expect(ExternalCommandLine.firstURL(in: "Uploaded to https://i.example.com/abc.png.\nDelete: https://x.y/d") ==
                "https://i.example.com/abc.png")
        #expect(ExternalCommandLine.firstURL(in: "(see ftp://host/file)") == "ftp://host/file")
        #expect(ExternalCommandLine.firstURL(in: "no link here") == nil)
    }
}

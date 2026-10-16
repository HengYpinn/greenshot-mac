// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct DestinationTests {
    @Test func notificationLevels() {
        #expect(NotificationLevel.all.shows(.info))
        #expect(!NotificationLevel.warnings.shows(.info) && NotificationLevel.warnings.shows(.warning))
        #expect(!NotificationLevel.errors.shows(.warning) && NotificationLevel.errors.shows(.error))
        #expect(!NotificationLevel.none.shows(.error))
    }

    @Test func recipientsAndMailto() throws {
        #expect(DestinationSupport.recipients(" a@b.c, d@e.f;g@h.i ,") == ["a@b.c", "d@e.f", "g@h.i"])
        let url = try #require(DestinationSupport.mailtoURL(to: ["a@b.c"], cc: ["d@e.f"], bcc: [], subject: "Screenshot & more"))
        #expect(url.absoluteString == "mailto:a@b.c?cc=d@e.f&subject=Screenshot%20%26%20more")
        #expect(DestinationSupport.mailtoURL(to: [], cc: [], bcc: [], subject: "")?.absoluteString == "mailto:")
    }

    @Test func uniqueFileNameWhenOverwriteIsOff() {
        let taken: Set<String> = ["/tmp/shot.png", "/tmp/shot (2).png"]
        let url = DestinationSupport.uniqueURL(for: URL(fileURLWithPath: "/tmp/shot.png")) { taken.contains($0.path) }
        #expect(url.path == "/tmp/shot (3).png")
        let free = DestinationSupport.uniqueURL(for: URL(fileURLWithPath: "/tmp/other.png")) { taken.contains($0.path) }
        #expect(free.path == "/tmp/other.png")
    }

    @Test func clipboardHTMLSnippet() {
        let html = DestinationSupport.htmlSnippet(png: Data([1, 2, 3]), width: 10, height: 20)
        #expect(html == "<img src=\"data:image/png;base64,AQID\" width=\"10\" height=\"20\">")
    }
}

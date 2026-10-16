// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct UpdateCheckTests {
    @Test func comparesVersionsNumberByNumber() {
        #expect(UpdateCheck.isNewer("v1.10", than: "1.9"))
        #expect(UpdateCheck.isNewer("2.0.1", than: "2.0"))
        #expect(!UpdateCheck.isNewer("1.2", than: "1.2.0"))
        #expect(!UpdateCheck.isNewer("1.2.0-beta", than: "1.2"))
        #expect(!UpdateCheck.isNewer("0.9", than: "1.0"))
        #expect(UpdateCheck.normalized(" V3.1 ") == "3.1")
    }

    @Test func dueAfterTheInterval() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        #expect(UpdateCheck.isDue(lastCheck: nil, intervalDays: 14, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-13 * 86_400), intervalDays: 14, now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-14 * 86_400), intervalDays: 14, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: nil, intervalDays: 0, now: now))
    }

    @Test func readsGitHubsLatestRelease() {
        let json = #"{"tag_name": "v1.4.0", "html_url": "https://github.com/HengYpinn/greenshot-mac/releases/tag/v1.4.0", "draft": false}"#
        let release = UpdateCheck.release(fromJSON: Data(json.utf8))
        #expect(release?.version == "1.4.0")
        #expect(release?.pageURL.absoluteString == "https://github.com/HengYpinn/greenshot-mac/releases/tag/v1.4.0")
        #expect(UpdateCheck.release(fromJSON: Data(#"{"message": "Not Found"}"#.utf8)) == nil)
        #expect(UpdateCheck.release(fromJSON: Data("nonsense".utf8)) == nil)
    }
}

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

    @Test func latestReleaseIgnoresPrereleases() {
        let json = #"{"tag_name": "v1.5.0-beta.1", "html_url": "https://github.com/HengYpinn/greenshot-mac/releases/tag/v1.5.0-beta.1", "prerelease": true}"#
        #expect(UpdateCheck.release(fromJSON: Data(json.utf8)) == nil)
    }

    @Test func comparesPrereleases() {
        #expect(UpdateCheck.isNewer("1.5.0", than: "1.5.0-beta.2"))
        #expect(UpdateCheck.isNewer("1.5.0-beta.2", than: "1.5.0-beta.1"))
        #expect(UpdateCheck.isNewer("1.5.0-beta.1", than: "1.4.9"))
        #expect(UpdateCheck.isNewer("1.5.0-beta.10", than: "1.5.0-beta.9"))
        #expect(UpdateCheck.isNewer("1.5.0-rc.1", than: "1.5.0-beta.3"))
        #expect(UpdateCheck.isNewer("1.5.0-beta.1", than: "1.5.0-beta"))
        #expect(!UpdateCheck.isNewer("1.5.0-beta.1", than: "1.5.0"))
        #expect(!UpdateCheck.isNewer("1.5.0-beta.1", than: "1.5.0-beta.1"))
        #expect(!UpdateCheck.isNewer("1.5.0+7", than: "1.5.0+3"))
        #expect(UpdateCheck.numbers("v1.5.0-beta.2+9") == [1, 5, 0])
    }

    @Test func picksTheNewestFromTheReleaseList() {
        func entry(_ tag: String, prerelease: Bool = false, draft: Bool = false) -> String {
            #"{"tag_name": "\#(tag)", "html_url": "https://github.com/HengYpinn/greenshot-mac/releases/tag/\#(tag)", "prerelease": \#(prerelease), "draft": \#(draft)}"#
        }
        let json = "[" + [entry("v1.6.0", draft: true), entry("v1.5.0-beta.2", prerelease: true), entry("v1.4.1"),
                          entry("v1.5.0-beta.1", prerelease: true), entry("v1.4.0")].joined(separator: ",") + "]"
        let data = Data(json.utf8)
        let beta = UpdateCheck.newestRelease(fromListJSON: data, includePrereleases: true)
        #expect(beta?.version == "1.5.0-beta.2" && beta?.isPrerelease == true)
        let stable = UpdateCheck.newestRelease(fromListJSON: data, includePrereleases: false)
        #expect(stable?.version == "1.4.1" && stable?.isPrerelease == false)
        #expect(UpdateCheck.newestRelease(fromListJSON: Data("[]".utf8), includePrereleases: true) == nil)
        #expect(UpdateCheck.newestRelease(fromListJSON: Data(#"{"message": "Not Found"}"#.utf8), includePrereleases: true) == nil)
        #expect(UpdateCheck.newestRelease(fromListJSON: Data("nonsense".utf8), includePrereleases: true) == nil)
    }
}

struct UpdateOutcomeTests {
    private let page = URL(string: "https://github.com/HengYpinn/greenshot-mac/releases/tag/v1.3")!

    @Test func newerReleaseWinsEvenWhenTheCheckFailedLater() {
        let release = UpdateCheck.Release(version: "1.3", pageURL: page)
        #expect(UpdateCheck.outcome(release: release, failed: false, current: "1.2") == .newer(release))
    }

    @Test func sameOrOlderReleaseIsUpToDate() {
        let release = UpdateCheck.Release(version: "1.2.0", pageURL: page)
        #expect(UpdateCheck.outcome(release: release, failed: false, current: "1.2") == .upToDate(latest: "1.2.0"))
        #expect(UpdateCheck.outcome(release: nil, failed: false, current: "1.2") == .upToDate(latest: nil))
    }

    @Test func failureWithoutReleaseIsFailed() {
        #expect(UpdateCheck.outcome(release: nil, failed: true, current: "1.2") == .failed)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

import Foundation
import Testing
@testable import GreenshotCore

struct PathContainmentTests {
    private let home = URL(fileURLWithPath: "/Users/me")
    private func context(title: String?, metadata: [String: String] = [:]) -> FilenamePattern.Context {
        FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: title, userName: "me", hostName: "mac",
                                homeDirectory: home, timeZone: TimeZone(identifier: "UTC")!, nextNumber: { 1 }, metadata: metadata)
    }

    // S3
    @Test func graphemeClustersDoNotHideASlash() {
        let tricks = ["a\u{0600}/b/\u{0301}c", "x/\u{200D}y", "p:\u{0301}q", "r\u{0600}\u{0001}s"]
        for trick in tricks {
            for cleaned in [FilenamePattern.makeFilenameSafe(trick)] {
                #expect(!cleaned.utf8.contains(0x2F))
                #expect(!cleaned.utf8.contains(0x3A))
                #expect(!cleaned.utf8.contains(where: { $0 < 0x20 }))
            }
        }
        #expect(!FilenamePattern.makePathSafe("a\"\u{0301}b|\u{200D}c").utf8.contains(0x22))
        #expect(FilenamePattern.makeFilenameSafe("..") == "_")
        #expect(FilenamePattern.makeFilenameSafe("...") == "...")
    }

    // S1
    @Test func aTitleStaysOneFolderLevelInTheOutputFolder() {
        let folder = DestinationSupport.outputFolder("${MyPictures}/${title}", context: context(title: "../../Library/Application Support/Foo"))
        #expect(FilenamePattern.isInside(folder, folder: URL(fileURLWithPath: "/Users/me/Pictures")))
        #expect(folder.deletingLastPathComponent().path == "/Users/me/Pictures")
        let viaMetadata = DestinationSupport.outputFolder("${MyPictures}/${url}", context: context(title: "t", metadata: ["url": "../../x"]))
        #expect(viaMetadata.deletingLastPathComponent().path == "/Users/me/Pictures")
    }

    @Test func aTitleDoesNotExpandToTheHomeFolder() {
        let folder = DestinationSupport.outputFolder("${title}", context: context(title: "~/x"))
        #expect(!folder.path.hasPrefix("/Users/me"))
        #expect(!folder.path.contains("/x"))
        #expect(DestinationSupport.outputFolder("~/Shots", context: context(title: "t")).path == "/Users/me/Shots")
        #expect(DestinationSupport.outputFolder("${HOME}/Shots", context: FilenamePattern.Context(
            captureTime: Date(), title: "t", environment: ["HOME": "/Users/me"], homeDirectory: home)).path == "/Users/me/Shots")
    }

    @Test func aVideoFolderStaysInsideItsFixedStart() {
        let url = RecordingOutputPath.url(folder: "~/Movies/${title}", pattern: "rec", context: context(title: "../../x"),
                                          exists: { _ in false })
        defer { RecordingOutputPath.release(url) }
        #expect(FilenamePattern.isInside(url, folder: URL(fileURLWithPath: "/Users/me/Movies")))
    }

    // R3
    @Test func aRecipeFilePatternStaysInItsDirectory() {
        let url = RecordingOutputPath.recipeURL(outputFilePath: nil, outputDirectory: "~/Clips", filenamePattern: "../../x.mp4",
                                                date: Date(timeIntervalSince1970: 0), environment: [:], homeDirectory: home,
                                                timeZone: TimeZone(identifier: "UTC")!)
        #expect(FilenamePattern.isInside(url, folder: URL(fileURLWithPath: "/Users/me/Clips")))
        let absolute = RecordingOutputPath.recipeURL(outputFilePath: nil, outputDirectory: "~/Clips", filenamePattern: "/etc/x.mp4",
                                                     date: Date(timeIntervalSince1970: 0), environment: [:], homeDirectory: home,
                                                     timeZone: TimeZone(identifier: "UTC")!)
        #expect(FilenamePattern.isInside(absolute, folder: URL(fileURLWithPath: "/Users/me/Clips")))
    }

    // S2
    @Test func onlyWebLinksComeOutOfCommandOutput() {
        #expect(ExternalCommandLine.firstWebLink(in: "file:///Applications/Calculator.app") == nil)
        #expect(ExternalCommandLine.firstWebLink(in: #"{"url":"smb://x/y"}"#) == nil)
        #expect(ExternalCommandLine.firstWebLink(in: "done https://example.com/a.") == URL(string: "https://example.com/a"))
    }

    // N2
    @Test func boxAndDropboxLinksAreCheckedOnTheirOwnDomains() throws {
        let fallback = URL(string: "https://app.box.com/file/1")!
        let bad = ["file:///etc/passwd", "https://evil.example/x", "https://evilbox.com/s/1", "https://box.com.evil.example/s",
                   "https://user@box.com/s", "http://app.box.com/s"]
        for link in bad {
            let data = Data(#"{"shared_link":{"url":"\#(link)"}}"#.utf8)
            #expect(try BoxClient.sharedLink(fromJSON: data, fallback: fallback) == fallback)
            #expect(throws: (any Error).self) { try BoxClient.sharedLink(fromJSON: data) }
        }
        let good = Data(#"{"shared_link":{"url":"https://app.box.com/s/abc"}}"#.utf8)
        #expect(try BoxClient.sharedLink(fromJSON: good, fallback: fallback) == URL(string: "https://app.box.com/s/abc"))
        let dropFallback = URL(string: "https://www.dropbox.com/home")!
        for link in ["file:///x", "https://evildropbox.com/s", "https://dropbox.com.evil.example/s"] {
            let data = Data(#"{"url":"\#(link)"}"#.utf8)
            #expect(try DropboxClient.sharedLink(fromJSON: data, fallback: dropFallback) == dropFallback)
        }
        let list = Data(#"{"links":[{"url":"https://www.dropbox.com/s/abc?dl=0"}]}"#.utf8)
        #expect(try DropboxClient.sharedLink(fromJSON: list, fallback: dropFallback) == URL(string: "https://www.dropbox.com/s/abc?dl=0"))
    }

    @Test func theUpdatePageIsThisProjectsReleases() {
        for page in ["file:///x", "https://evil.example/HengYpinn/greenshot-mac/releases/tag/v9", "https://github.com/evil/repo/releases",
                     "https://github.com.evil.example/HengYpinn/greenshot-mac/releases", "https://github.com/HengYpinn/greenshot-mac/releases-evil"] {
            let json = Data(#"{"tag_name":"v9.0","html_url":"\#(page)"}"#.utf8)
            #expect(UpdateCheck.release(fromJSON: json)?.pageURL == UpdateCheck.releasesPageURL)
        }
        let json = Data(#"{"tag_name":"v9.0","html_url":"https://github.com/HengYpinn/greenshot-mac/releases/tag/v9.0"}"#.utf8)
        #expect(UpdateCheck.release(fromJSON: json)?.pageURL.absoluteString == "https://github.com/HengYpinn/greenshot-mac/releases/tag/v9.0")
    }
}

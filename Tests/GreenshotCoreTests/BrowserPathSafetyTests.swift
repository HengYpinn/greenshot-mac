// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Review S-M1: a web page's title and address (TAB_CHANGED, IMPORT_CAPTURE) must not choose the folder a screenshot is
/// written to, neither through the file name pattern nor through the output folder pattern.
struct BrowserPathSafetyTests {
    private let home = URL(fileURLWithPath: "/Users/me")
    private static let hostile = "../../../../Library/Application Support/SomeApp/x"

    private func context(_ store: CaptureMetadataStore, date: Date, title: String = "Safari") -> FilenamePattern.Context {
        FilenamePattern.Context(captureTime: date, title: title, homeDirectory: home,
                                metadata: store.patternMetadata(forCaptureAt: date))
    }

    @Test func aPageTitleOrAddressAddsNoFolders() {
        let tab = BrowserContext()
        tab.update(url: "https://evil.example/?/../../Desktop/x", title: Self.hostile)
        let store = CaptureMetadataStore(browser: tab)
        let date = Date()
        store.record(["url": "https://evil.example/../../Desktop/y"], forCaptureAt: date)
        let pattern = context(store, date: date)
        for variable in ["${Browser.Title}", "${Browser.Url}", "${url}"] {
            let name = FilenamePattern.fileName(variable, context: pattern)
            #expect(!name.contains("/"), "\(variable): \(name)")
        }
    }

    @Test func theOutputFolderStaysInItsFixedStart() {
        let tab = BrowserContext()
        tab.update(url: "https://evil.example/", title: Self.hostile)
        let store = CaptureMetadataStore(browser: tab)
        let date = Date()
        // The output folder is filled without file name cleaning; the values come cleaned from the store
        let folder = DestinationSupport.outputFolder("~/Shots/${Browser.Title}", context: context(store, date: date))
        let root = URL(fileURLWithPath: "/Users/me/Shots")
        #expect(FilenamePattern.isInside(folder, folder: root))
    }

    @Test func metadataIsCleanedLikeTheTitle() {
        let pattern = FilenamePattern.Context(captureTime: Date(), title: "x", metadata: ["a": "../x", "b": "..", "c": "a/b:c"])
        #expect(FilenamePattern.fill("${a}", context: pattern) == ".._x")
        #expect(FilenamePattern.fill("${b}", context: pattern) == "_")
        #expect(FilenamePattern.fill("${c}", context: pattern) == "a_b_c")
        // Texts that aren't paths (mail subject, print footer) keep them
        #expect(FilenamePattern.fill("${c}", context: pattern, filenameSafe: false) == "a/b:c")
    }

    @Test func relativeNamesStayInTheFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/Shots", isDirectory: true)
        #expect(FilenamePattern.file(named: "2026/10/shot", in: folder).path == "/Users/me/Shots/2026/10/shot")
        #expect(FilenamePattern.file(named: "../Desktop/shot", in: folder).path == "/Users/me/Shots/.._Desktop_shot")
        #expect(FilenamePattern.file(named: "a/../../b", in: folder).path == "/Users/me/Shots/a_.._.._b")
        #expect(FilenamePattern.file(named: ".", in: folder).path == "/Users/me/Shots/_")
        // A pattern that is itself absolute writes where it says
        #expect(FilenamePattern.file(named: "/Volumes/Backup/shot", in: folder).path == "/Volumes/Backup/shot")
    }

    @Test func insideAfterDotsAreResolved() {
        let folder = URL(fileURLWithPath: "/Users/me/Shots")
        #expect(FilenamePattern.isInside(URL(fileURLWithPath: "/Users/me/Shots"), folder: folder))
        #expect(FilenamePattern.isInside(URL(fileURLWithPath: "/Users/me/Shots/a/../b"), folder: folder))
        #expect(!FilenamePattern.isInside(URL(fileURLWithPath: "/Users/me/Shots/../Library"), folder: folder))
        #expect(!FilenamePattern.isInside(URL(fileURLWithPath: "/Users/me/Shotsy"), folder: folder))
    }

    @Test func fixedStartOfAFolderPattern() {
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "~/Shots/${YYYY}", home: home)?.path == "/Users/me/Shots")
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "/Volumes/X/${title}/${MM}", home: home)?.path == "/Volumes/X")
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "/Users/me/Shots", home: home)?.path == "/Users/me")
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "${MyPictures}/Greenshot", home: home) == nil)
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "Shots/${title}", home: home) == nil)
        #expect(FilenamePattern.literalRoot(ofFolderPattern: "", home: home) == nil)
    }

    @Test func aTitleThatLeavesTheFixedStartIsNoticed() {
        // ${title} keeps "/" in the output folder pattern (upstream fills it without cleaning); ImageSaver refuses the
        // result when it leaves the pattern's fixed start
        let pattern = "~/Shots/${title}"
        let filled = DestinationSupport.outputFolder(pattern, context: FilenamePattern.Context(captureTime: Date(), title: "../../Library",
                                                                                              homeDirectory: home))
        let root = FilenamePattern.literalRoot(ofFolderPattern: pattern, home: home)
        let fixed = URL(fileURLWithPath: "/Users/me/Shots")
        #expect(root?.standardizedFileURL.path == fixed.path)
        #expect(!FilenamePattern.isInside(filled, folder: fixed))
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct DestinationFolderTests {
    private func context(counter: @escaping () -> UInt = { 7 }) -> FilenamePattern.Context {
        FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 1_790_000_000), title: "Safari",
                                environment: ["TEAM": "QA"], homeDirectory: URL(fileURLWithPath: "/Users/me"),
                                timeZone: TimeZone(identifier: "UTC")!, nextNumber: counter)
    }

    @Test func outputFolderFillsVariablesAndExpandsHome() {
        #expect(DestinationSupport.outputFolder("~/Pictures/${YYYY}-${MM}", context: context()).path == "/Users/me/Pictures/2026-09")
        #expect(DestinationSupport.outputFolder("/Volumes/Shots/${TEAM}", context: context()).path == "/Volumes/Shots/QA")
        #expect(DestinationSupport.outputFolder("  ", context: context()).path == "/Users/me/Desktop")
    }

    @Test func numberInFolderAndNameCountsOnce() {
        // The folder only previews ${NUM} (consumeNumber: false gives current + 1), the name counts it up.
        var counter: UInt = 41
        let preview = context(counter: { counter + 1 })
        let counting = context(counter: { counter += 1; return counter })
        let folder = DestinationSupport.outputFolder("/shots/${NUM}", context: preview)
        let name = FilenamePattern.fileName("${NUM}", context: counting)
        #expect(folder.lastPathComponent == "000042" && name == "000042")
    }

    @Test func subfolderOfAFilledPattern() {
        #expect(DestinationSupport.subfolder(ofFileName: "2026-10-17/000001 - Safari") == "2026-10-17")
        #expect(DestinationSupport.subfolder(ofFileName: "2026/10/shot") == "2026/10")
        #expect(DestinationSupport.subfolder(ofFileName: "shot") == nil)
        #expect(DestinationSupport.subfolder(ofFileName: "/absolute/shot") == nil)
    }

    @Test func saveAsStartsInTheRightFolder() {
        let output = URL(fileURLWithPath: "/Users/me/Desktop")
        let sub = URL(fileURLWithPath: "/Users/me/Desktop/2026-10-17")
        let editorFile = URL(fileURLWithPath: "/Users/me/Documents/shot.png")
        let exists: (URL) -> Bool = { $0.path == "/Users/me/Pictures" }
        // The editor's own file first, then the pattern's sub folder, then the last saved file's folder, then the output folder.
        #expect(DestinationSupport.saveAsFolder(editorFile: editorFile, patternSubfolder: sub, lastSavedFile: "/Users/me/Pictures/a.png",
                                                outputFolder: output, folderExists: exists).path == "/Users/me/Documents")
        #expect(DestinationSupport.saveAsFolder(editorFile: nil, patternSubfolder: sub, lastSavedFile: "/Users/me/Pictures/a.png",
                                                outputFolder: output, folderExists: exists) == sub)
        #expect(DestinationSupport.saveAsFolder(editorFile: nil, patternSubfolder: nil, lastSavedFile: "/Users/me/Pictures/a.png",
                                                outputFolder: output, folderExists: exists).path == "/Users/me/Pictures")
        #expect(DestinationSupport.saveAsFolder(editorFile: nil, patternSubfolder: nil, lastSavedFile: "/gone/a.png",
                                                outputFolder: output, folderExists: exists) == output)
        #expect(DestinationSupport.saveAsFolder(editorFile: nil, patternSubfolder: nil, lastSavedFile: nil,
                                                outputFolder: output, folderExists: exists) == output)
    }

    @Test func eagerFolderGoesOnlyWhenNothingWasSaved() {
        #expect(DestinationSupport.isUnused(folderContents: []))
        #expect(DestinationSupport.isUnused(folderContents: [".DS_Store"]))
        #expect(!DestinationSupport.isUnused(folderContents: ["shot.png"]))
        #expect(!DestinationSupport.isUnused(folderContents: [".DS_Store", "later"]))
    }

    @Test func oldTemporaryFoldersAreChosenByAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = URL(fileURLWithPath: "/tmp/Greenshot/a")
        let old = URL(fileURLWithPath: "/tmp/Greenshot/b")
        let stale = DestinationSupport.staleTemporaryFolders([(fresh, now.addingTimeInterval(-3600)),
                                                             (old, now.addingTimeInterval(-25 * 3600))], now: now)
        #expect(stale == [old])
    }

    @Test func printersDefaultFirstThenByName() {
        #expect(DestinationSupport.sortedPrinters(["Office B", "Home", "Office A", "Home"], defaultPrinter: "Office B")
                == ["Office B", "Home", "Office A"])
        #expect(DestinationSupport.sortedPrinters(["b", "A"], defaultPrinter: nil) == ["A", "b"])
    }

    @Test func qualityDialogControls() {
        #expect(DestinationSupport.usesQuality(.jpg) && !DestinationSupport.usesQuality(.png))
        #expect(DestinationSupport.reducesColors(.png) && DestinationSupport.reducesColors(.gif) && !DestinationSupport.reducesColors(.jpg))
        #expect(DestinationSupport.asksQuality(.jpg) && DestinationSupport.asksQuality(.png))
        #expect(!DestinationSupport.asksQuality(.pdf) && !DestinationSupport.asksQuality(.greenshot))
    }

    /// The dialog asks for what the exporter uses: the quality for JPEG alone (WebP is written lossless), "Reduce
    /// colours" for every format whose colours the exporter reduces (BMP, TIFF, WebP, … too).
    @Test func qualityDialogFollowsTheExporter() {
        for format in ImageFormat.allCases {
            #expect(DestinationSupport.usesQuality(format) == format.usesQuality, "\(format)")
            #expect(DestinationSupport.reducesColors(format) == format.reducesColors, "\(format)")
        }
        #expect(!DestinationSupport.usesQuality(.webp) && DestinationSupport.reducesColors(.webp))
        #expect(DestinationSupport.asksQuality(.bmp) && DestinationSupport.asksQuality(.tiff))
    }

    @Test func dontAskAgainKeepsTheChoices() {
        var settings = AppSettings()
        settings.promptJpegQuality = true
        settings.rememberQualityChoice(jpegQuality: 65, reduceColors: true)
        #expect(settings.jpegQuality == 65 && settings.reduceColors && !settings.promptJpegQuality)
        settings.rememberQualityChoice(jpegQuality: 0, reduceColors: false)
        #expect(settings.jpegQuality == 1 && !settings.reduceColors)
    }
}

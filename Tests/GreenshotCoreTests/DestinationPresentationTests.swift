// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct DestinationPresentationTests {
    @Test func pickerOrderIsPriorityThenOrdinalName() {
        // Upstream DestinationComparer: priority first, then the names compared character by character.
        let entries: [(priority: Int, title: String)] = [
            (10, "Upload to Jira…"), (1, "Open in Image Editor"), (0, "Save as PDF…"), (2, "Print…"),
            (0, "Save Directly (~/Desktop)"), (10, "External: Preview"), (0, "Save As…"), (2, "Copy to Clipboard"),
        ]
        let sorted = DestinationOrder.sorted(entries) { $0 }.map(\.title)
        #expect(sorted == ["Save As…", "Save Directly (~/Desktop)", "Save as PDF…", "Open in Image Editor",
                           "Copy to Clipboard", "Print…", "External: Preview", "Upload to Jira…"])
    }

    @Test func sortingKeepsTheOrderOfEqualEntries() {
        let entries = [(priority: 4, title: "Same", tag: 1), (priority: 4, title: "Same", tag: 2), (priority: 3, title: "Z", tag: 3)]
        #expect(DestinationOrder.sorted(entries) { ($0.priority, $0.title) }.map(\.tag) == [3, 1, 2])
    }

    @Test func everyDestinationHasATitleSymbolAndUpstreamPriority() {
        for destination in CaptureDestination.allCases {
            #expect(!destination.pickerTitle.isEmpty)
            #expect(!destination.symbolName.isEmpty)
        }
        #expect(CaptureDestination.file.pickerPriority == 0 && CaptureDestination.fileAs.pickerPriority == 0)
        #expect(CaptureDestination.editor.pickerPriority == 1)
        #expect(CaptureDestination.clipboard.pickerPriority == 2 && CaptureDestination.printer.pickerPriority == 2)
        #expect(CaptureDestination.email.pickerPriority == 3 && CaptureDestination.qrCode.pickerPriority == 4)
        #expect(CaptureDestination.jira.pickerPriority == 10 && CaptureDestination.externalCommand.pickerPriority == 10)
    }

    @Test func shortcutsMatchTheFileMenu() {
        #expect(CaptureDestination.file.shortcut == DestinationShortcut("s"))
        #expect(CaptureDestination.fileAs.shortcut == DestinationShortcut("s", shift: true))
        #expect(CaptureDestination.pdf.shortcut == DestinationShortcut("p", option: true))
        #expect(CaptureDestination.clipboard.shortcut?.displayString == "⇧⌘C")
        #expect(CaptureDestination.printer.shortcut?.displayString == "⌘P")
        #expect(CaptureDestination.ocr.shortcut?.displayString == "⌥⌘T")
        #expect(CaptureDestination.email.shortcut?.displayString == "⌘E")
        #expect(CaptureDestination.share.shortcut == nil)
    }

    @Test func uploadsAreOfferedOnceSetUp() {
        var settings = AppSettings()
        for upload in [CaptureDestination.jira, .confluence, .box, .dropbox] {
            #expect(!DestinationAvailability.isSetUp(upload, in: settings))
        }
        settings.jira.url = "https://example.atlassian.net"
        settings.confluence.url = " "
        settings.box.clientID = "client"
        settings.dropbox.appKey = "key"
        #expect(DestinationAvailability.isSetUp(.jira, in: settings))
        #expect(!DestinationAvailability.isSetUp(.confluence, in: settings))
        #expect(DestinationAvailability.isSetUp(.box, in: settings) && DestinationAvailability.isSetUp(.dropbox, in: settings))
        #expect(DestinationAvailability.isSetUp(.clipboard, in: settings))
        #expect(!DestinationAvailability.isSetUp(.picker, in: settings))
    }

    @Test func menuTitlesAreCut() {
        #expect(FilenamePattern.menuTitle("Quarterly report") == "Quarterly report")
        #expect(FilenamePattern.menuTitle("A very long window title here") == "A very long window t…")
        #expect(FilenamePattern.menuTitle("Two\nlines", length: 40) == "Two lines")
    }
}

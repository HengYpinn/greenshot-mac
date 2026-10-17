// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The apps Greenshot sends captures to by AppleScript: upstream's Office plugin (`Greenshot.Plugin.Office`: Word,
/// Excel, PowerPoint, Outlook, OneNote), Apple Notes in OneNote's place (OneNote for Mac has no AppleScript dictionary),
/// and Apple Mail for e-mails with CC and BCC.
public enum OfficeApplication: String, CaseIterable, Sendable {
    case word, excel, powerpoint, outlook, notes, mail

    public var bundleID: String {
        switch self {
        case .word: return "com.microsoft.Word"
        case .excel: return "com.microsoft.Excel"
        case .powerpoint: return "com.microsoft.Powerpoint"
        case .outlook: return "com.microsoft.Outlook"
        case .notes: return "com.apple.Notes"
        case .mail: return "com.apple.mail"
        }
    }

    public var name: String {
        switch self {
        case .word: return "Microsoft Word"
        case .excel: return "Microsoft Excel"
        case .powerpoint: return "Microsoft PowerPoint"
        case .outlook: return "Microsoft Outlook"
        case .notes: return "Notes"
        case .mail: return "Mail"
        }
    }

    /// The destination of the app; Mail is the Email destination's.
    public var destination: CaptureDestination {
        switch self {
        case .word: return .word
        case .excel: return .excel
        case .powerpoint: return .powerpoint
        case .outlook: return .outlook
        case .notes: return .notes
        case .mail: return .email
        }
    }

    public init?(destination: CaptureDestination) {
        guard let app = Self.allCases.first(where: { $0.destination == destination && $0 != .mail }) else { return nil }
        self = app
    }

    /// Whether the app has documents or messages of its own to add the capture to (upstream's dynamic destinations).
    public var hasOpenItems: Bool { self != .notes }
}

/// The scripts of the Office destinations (ports of upstream `WordExporter`, `ExcelExporter`, `PowerpointExporter`,
/// `OutlookEmailExporter`, `MapiMailMessage`), and Notes. Each is fixed text plus arguments; see `AppleScriptCall`.
public enum OfficeScripts {
    // MARK: Word (upstream WordExporter)

    /// Inserts the picture into a new document (`documentName` empty) or at the insertion point of an open one, locks
    /// its aspect ratio when asked (`WordLockAspectRatio`), shows it at 100 % (upstream) and answers the document's name.
    public static func wordInsert(imagePath: String, documentName: String?, lockAspectRatio: Bool) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set documentName to item 2 of argv
            set pictureFile to (POSIX file imagePath) as text
            tell application id "com.microsoft.Word"
                if documentName is "" then
                    set targetDocument to make new document
                    set thePicture to make new inline picture at end of text object of targetDocument with properties {file name:pictureFile, save with document:true}
                else
                    set targetDocument to document documentName
                    activate object targetDocument
                    set insertionPoint to collapse range (text object of selection) direction collapse end
                    set thePicture to make new inline picture at insertionPoint with properties {file name:pictureFile, save with document:true}
                end if
                set lock aspect ratio of thePicture to \(lockAspectRatio)
                try
                    set percentage of zoom of view of active window to 100
                end try
                activate
                return name of targetDocument
            end tell
        end run
        """, arguments: [imagePath, documentName ?? ""], bundleID: OfficeApplication.word.bundleID)
    }

    /// The names of the open documents that can be changed (upstream `GetWordDocuments` leaves out read-only ones).
    public static func wordDocuments() -> AppleScriptCall {
        listScript(OfficeApplication.word.bundleID, elements: "documents", condition: "read only of anItem is false")
    }

    // MARK: Excel (upstream ExcelExporter)

    /// Inserts the picture into a new workbook (`workbookName` empty) or the active sheet of an open one, at 40/40 points
    /// with its own size and a locked aspect ratio (upstream), and answers the workbook's name.
    public static func excelInsert(imagePath: String, workbookName: String?, size: CGSize) -> AppleScriptCall {
        let width = String(Int(size.width.rounded()))
        let height = String(Int(size.height.rounded()))
        return AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set workbookName to item 2 of argv
            set pictureWidth to (item 3 of argv) as integer
            set pictureHeight to (item 4 of argv) as integer
            set pictureFile to (POSIX file imagePath) as text
            tell application id "com.microsoft.Excel"
                if workbookName is "" then
                    set targetWorkbook to make new workbook
                else
                    set targetWorkbook to workbook workbookName
                end if
                activate object targetWorkbook
                set thePicture to make new picture at beginning of active sheet of targetWorkbook with properties {file name:pictureFile, top:40, left position:40, width:pictureWidth, height:pictureHeight}
                set lock aspect ratio of thePicture to true
                activate
                return name of targetWorkbook
            end tell
        end run
        """, arguments: [imagePath, workbookName ?? "", width, height], bundleID: OfficeApplication.excel.bundleID)
    }

    public static func excelWorkbooks() -> AppleScriptCall {
        listScript(OfficeApplication.excel.bundleID, elements: "workbooks", condition: nil)
    }

    // MARK: PowerPoint (upstream PowerpointExporter)

    /// First step: a new slide at the end of a new (`presentationName` empty) or an open presentation, with the layout
    /// (blank when PowerPoint refuses it), the title in its first shape when it has a caption and a picture placeholder.
    /// Answers "presentation name, slide index, slide width, slide height[, placeholder left, top, width, height]",
    /// tab-separated, in points; see `PowerPointSlide`.
    public static func powerPointSlide(presentationName: String?, layout: OfficeSettings.SlideLayout, title: String) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set presentationName to item 1 of argv
            set slideTitle to item 2 of argv
            tell application id "com.microsoft.Powerpoint"
                if presentationName is "" then
                    set targetPresentation to make new presentation
                else
                    set targetPresentation to presentation presentationName
                end if
                try
                    set theSlide to make new slide at end of slides of targetPresentation with properties {layout:slide layout \(layout.appleScriptName)}
                on error
                    set theSlide to make new slide at end of slides of targetPresentation with properties {layout:slide layout blank}
                end try
                set answer to (name of targetPresentation) & tab & ((slide index of theSlide) as integer)
                set answer to answer & tab & ((slide width of page setup of targetPresentation) as integer)
                set answer to answer & tab & ((slide height of page setup of targetPresentation) as integer)
                if (count of shapes of theSlide) >= 2 then
                    try
                        set content of text range of text frame of shape 1 of theSlide to slideTitle
                    end try
                    set placeholder to shape 2 of theSlide
                    set answer to answer & tab & ((left position of placeholder) as integer) & tab & ((top of placeholder) as integer)
                    set answer to answer & tab & ((width of placeholder) as integer) & tab & ((height of placeholder) as integer)
                end if
                return answer
            end tell
        end run
        """, arguments: [presentationName ?? "", title], bundleID: OfficeApplication.powerpoint.bundleID)
    }

    /// Second step: the picture on the slide in `frame` (points, see `OfficeLayout.pictureFrame`), aspect ratio locked
    /// when asked (`PowerpointLockAspectRatio`), then the slide shown.
    public static func powerPointPicture(presentationName: String, slideIndex: Int, imagePath: String, frame: CGRect,
                                         lockAspectRatio: Bool) -> AppleScriptCall {
        let numbers = [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0.rounded())) }
        return AppleScriptCall(source: """
        on run argv
            set presentationName to item 1 of argv
            set slideNumber to (item 2 of argv) as integer
            set imagePath to item 3 of argv
            set pictureLeft to (item 4 of argv) as integer
            set pictureTop to (item 5 of argv) as integer
            set pictureWidth to (item 6 of argv) as integer
            set pictureHeight to (item 7 of argv) as integer
            set pictureFile to (POSIX file imagePath) as text
            tell application id "com.microsoft.Powerpoint"
                set targetPresentation to presentation presentationName
                set theSlide to slide slideNumber of targetPresentation
                set thePicture to make new picture at end of shapes of theSlide with properties {file name:pictureFile, left position:pictureLeft, top:pictureTop, width:pictureWidth, height:pictureHeight}
                set lock aspect ratio of thePicture to \(lockAspectRatio)
                try
                    go to slide (view of document window 1) number slideNumber
                end try
                activate
                return name of targetPresentation
            end tell
        end run
        """, arguments: [presentationName, String(slideIndex), imagePath] + numbers, bundleID: OfficeApplication.powerpoint.bundleID)
    }

    /// The names of the open presentations that can be changed (upstream leaves out read-only ones).
    public static func powerPointPresentations() -> AppleScriptCall {
        listScript(OfficeApplication.powerpoint.bundleID, elements: "presentations", condition: "read only of anItem is false")
    }

    // MARK: Outlook (upstream OutlookEmailExporter)

    /// A new mail with the subject, the recipients and the picture attached, opened in its window. `format` gives a
    /// plain-text body for `.text`; Outlook's dictionary can't mark an attachment as inline, so the picture is attached
    /// in both formats.
    public static func outlookNewMail(imagePath: String, subject: String, to: [String], cc: [String], bcc: [String],
                                      format: OfficeSettings.EmailFormat) -> AppleScriptCall {
        let body = format == .text ? "\n            set plain text content of theMessage to \"\"" : ""
        return AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set theSubject to item 2 of argv
            set toList to paragraphs of item 3 of argv
            set ccList to paragraphs of item 4 of argv
            set bccList to paragraphs of item 5 of argv
            tell application id "com.microsoft.Outlook"
                set theMessage to make new outgoing message with properties {subject:theSubject}\(body)
                repeat with anAddress in toList
                    make new to recipient at theMessage with properties {email address:{address:(contents of anAddress)}}
                end repeat
                repeat with anAddress in ccList
                    make new cc recipient at theMessage with properties {email address:{address:(contents of anAddress)}}
                end repeat
                repeat with anAddress in bccList
                    make new bcc recipient at theMessage with properties {email address:{address:(contents of anAddress)}}
                end repeat
                make new attachment at theMessage with properties {file:(POSIX file imagePath)}
                open theMessage
                activate
            end tell
            return ""
        end run
        """, arguments: [imagePath, subject, AppleScriptCall.lines(to), AppleScriptCall.lines(cc), AppleScriptCall.lines(bcc)],
            bundleID: OfficeApplication.outlook.bundleID)
    }

    /// The open message windows: "id, title" lines (upstream `RetrievePossibleTargets` lists the open inspectors).
    public static func outlookOpenMessages() -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set answer to {}
            tell application id "com.microsoft.Outlook"
                repeat with aWindow in draft windows
                    try
                        set end of answer to ((id of aWindow) as text) & tab & (name of aWindow)
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to linefeed
            return answer as text
        end run
        """, bundleID: OfficeApplication.outlook.bundleID)
    }

    /// Attaches the picture to the message of an open window (upstream `ExportToInspector`).
    public static func outlookAttach(imagePath: String, windowID: String) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set windowID to (item 2 of argv) as integer
            tell application id "com.microsoft.Outlook"
                set targetWindow to first draft window whose id is windowID
                make new attachment at (object of targetWindow) with properties {file:(POSIX file imagePath)}
                activate
                return name of targetWindow
            end tell
        end run
        """, arguments: [imagePath, windowID], bundleID: OfficeApplication.outlook.bundleID)
    }

    // MARK: Mail (upstream MapiMailMessage)

    /// A new message in Mail with the subject, To, CC and BCC and the picture attached, in its window.
    public static func mailNewMessage(imagePath: String, subject: String, to: [String], cc: [String], bcc: [String]) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set theSubject to item 2 of argv
            set toList to paragraphs of item 3 of argv
            set ccList to paragraphs of item 4 of argv
            set bccList to paragraphs of item 5 of argv
            set theFile to (POSIX file imagePath) as alias
            tell application id "com.apple.mail"
                set theMessage to make new outgoing message with properties {subject:theSubject, visible:true}
                tell theMessage
                    repeat with anAddress in toList
                        make new to recipient at end of to recipients with properties {address:(contents of anAddress)}
                    end repeat
                    repeat with anAddress in ccList
                        make new cc recipient at end of cc recipients with properties {address:(contents of anAddress)}
                    end repeat
                    repeat with anAddress in bccList
                        make new bcc recipient at end of bcc recipients with properties {address:(contents of anAddress)}
                    end repeat
                    make new attachment with properties {file name:theFile} at after the last paragraph
                end tell
                activate
            end tell
            return ""
        end run
        """, arguments: [imagePath, subject, AppleScriptCall.lines(to), AppleScriptCall.lines(cc), AppleScriptCall.lines(bcc)],
            bundleID: OfficeApplication.mail.bundleID)
    }

    /// The messages being written: "id, subject" lines.
    public static func mailOpenMessages() -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set answer to {}
            tell application id "com.apple.mail"
                repeat with aMessage in outgoing messages
                    try
                        set end of answer to ((id of aMessage) as text) & tab & (subject of aMessage)
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to linefeed
            return answer as text
        end run
        """, bundleID: OfficeApplication.mail.bundleID)
    }

    /// Attaches the picture to a message being written.
    public static func mailAttach(imagePath: String, messageID: String) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set messageID to (item 2 of argv) as integer
            set theFile to (POSIX file imagePath) as alias
            tell application id "com.apple.mail"
                set theMessage to first outgoing message whose id is messageID
                tell theMessage
                    make new attachment with properties {file name:theFile} at after the last paragraph
                end tell
                activate
                return subject of theMessage
            end tell
        end run
        """, arguments: [imagePath, messageID], bundleID: OfficeApplication.mail.bundleID)
    }

    // MARK: Notes (in OneNote's place)

    /// A new note in the default folder named after the capture, with the picture (upstream OneNote: a new page in the
    /// default notebook), shown.
    public static func notesNewNote(imagePath: String, title: String) -> AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set imagePath to item 1 of argv
            set noteTitle to item 2 of argv
            tell application id "com.apple.Notes"
                set theNote to make new note at default folder of default account with properties {name:noteTitle}
                make new attachment at end of attachments of theNote with data (POSIX file imagePath)
                show theNote
                activate
            end tell
            return ""
        end run
        """, arguments: [imagePath, title], bundleID: OfficeApplication.notes.bundleID)
    }

    // MARK: Lists

    /// The names of an app's documents, one per line, optionally only those meeting `condition` (about `anItem`).
    static func listScript(_ bundleID: String, elements: String, condition: String?) -> AppleScriptCall {
        let add = "set end of answer to (name of anItem) as text"
        let line = condition.map { "if \($0) then \(add)" } ?? add
        return AppleScriptCall(source: """
        on run argv
            set answer to {}
            tell application id "\(bundleID)"
                repeat with anItem in \(elements)
                    try
                        \(line)
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to linefeed
            return answer as text
        end run
        """, bundleID: bundleID)
    }

    /// The open documents (or messages) an Office app lists for its picker entries, nil for Notes.
    public static func openItems(of app: OfficeApplication) -> AppleScriptCall? {
        switch app {
        case .word: return wordDocuments()
        case .excel: return excelWorkbooks()
        case .powerpoint: return powerPointPresentations()
        case .outlook: return outlookOpenMessages()
        case .mail: return mailOpenMessages()
        case .notes: return nil
        }
    }

    /// The items of an `openItems` answer: an id (the name for documents, the window or message id for messages) and a
    /// title.
    public static func openItems(of app: OfficeApplication, fromOutput output: String) -> [OfficeOpenItem] {
        switch app {
        case .outlook, .mail:
            return AppleScriptOutput.records(output).compactMap { fields in
                guard let id = fields.first, !id.isEmpty else { return nil }
                let title = fields.dropFirst().joined(separator: "\t")
                return OfficeOpenItem(id: id, title: title.isEmpty ? "New message" : title)
            }
        case .word, .excel, .powerpoint, .notes:
            return AppleScriptOutput.lines(output).map { OfficeOpenItem(id: $0, title: $0) }
        }
    }
}

/// An open document, workbook, presentation or message window an app lists (upstream's dynamic destinations).
public struct OfficeOpenItem: Equatable, Hashable, Sendable {
    /// What the export script finds it by: the name of a document, the id of a message window.
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

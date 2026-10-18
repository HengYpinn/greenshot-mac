// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreServices
import Foundation
import Testing
@testable import GreenshotCore

/// Text that would break a script if it were pasted into the source: quotes, backslashes, AppleScript's chevrons,
/// line breaks, a `"& do shell script "` injection attempt and non-ASCII.
private let nasty = "Q3zqx \"report\" \\ «data» & do shell script \"zqy\" –\nnext line 🙈"

/// Whether an app with this bundle identifier is installed (the compile checks need its dictionary).
func isInstalled(_ bundleID: String) -> Bool {
    guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] else {
        return false
    }
    return !urls.isEmpty
}

/// Compiles a script with `osacompile` against the installed app's dictionary (nothing is sent to the app). nil when it
/// compiles, else the error. Waits for the process off the cooperative pool: a test holding a pool thread for seconds
/// starves the tests that need one (the pool has as many threads as cores, 3 on CI).
func compileError(_ source: String) async throws -> String? {
    try await offPool { try compileErrorBlocking(source) }
}

private func compileErrorBlocking(_ source: String) throws -> String? {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-osacompile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let script = folder.appendingPathComponent("script.applescript")
    try Data(source.utf8).write(to: script)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
    process.arguments = ["-o", folder.appendingPathComponent("script.scpt").path, script.path]
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    let output = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? nil : String(decoding: output, as: UTF8.self)
}

let canCompile = FileManager.default.isExecutableFile(atPath: "/usr/bin/osacompile")

struct OfficeScriptsTests {
    private static let size = CGSize(width: 640, height: 400)

    /// Every script of the Office destinations, with the nasty text wherever the user's text goes.
    static func allCalls() -> [AppleScriptCall] {
        var calls: [AppleScriptCall] = [
            OfficeScripts.wordInsert(imagePath: "/tmp/" + nasty, documentName: nasty, lockAspectRatio: true),
            OfficeScripts.wordInsert(imagePath: "/tmp/a.png", documentName: nil, lockAspectRatio: false),
            OfficeScripts.wordDocuments(),
            OfficeScripts.excelInsert(imagePath: "/tmp/" + nasty, workbookName: nasty, size: size),
            OfficeScripts.excelWorkbooks(),
            OfficeScripts.powerPointSlide(presentationName: nasty, layout: .pictureWithCaption, title: nasty),
            OfficeScripts.powerPointPicture(presentationName: nasty, slideIndex: 3, imagePath: "/tmp/" + nasty,
                                            frame: CGRect(x: 10, y: 20, width: 300, height: 200), lockAspectRatio: true),
            OfficeScripts.powerPointPresentations(),
            OfficeScripts.outlookOpenMessages(),
            OfficeScripts.outlookOpenMessages(includeMeetings: true),
            OfficeScripts.outlookAttach(imagePath: "/tmp/" + nasty, windowID: "12"),
            OfficeScripts.outlookAttachToEvent(imagePath: "/tmp/" + nasty, windowID: "12"),
            OfficeScripts.mailNewMessage(imagePath: "/tmp/" + nasty, subject: nasty, to: [nasty], cc: [nasty], bcc: [nasty]),
            OfficeScripts.mailOpenMessages(),
            OfficeScripts.mailAttach(imagePath: "/tmp/" + nasty, messageID: "7"),
            OfficeScripts.notesNewNote(imagePath: "/tmp/" + nasty, title: nasty),
        ]
        for format in OfficeSettings.EmailFormat.allCases {
            calls.append(OfficeScripts.outlookNewMail(imagePath: "/tmp/" + nasty, subject: nasty, to: [nasty, "b@x.test"],
                                                      cc: [nasty], bcc: [], format: format))
        }
        return calls
    }

    @Test func userTextOnlyGoesIntoTheArguments() {
        for call in Self.allCalls() {
            #expect(!call.source.contains("zqx"), "\(call.source)")
            #expect(!call.source.contains("zqy"))
            let ascii = call.source.unicodeScalars.allSatisfy { $0.isASCII }
            #expect(ascii, "only ASCII in the script source: osascript reads it from standard input")
            #expect(call.processArguments.first == "-")
            #expect(call.source.contains("on run argv"))
        }
    }

    @Test func argumentsKeepTheTextAsItIs() {
        let word = OfficeScripts.wordInsert(imagePath: "/tmp/a b.png", documentName: nasty, lockAspectRatio: true)
        #expect(word.arguments == ["/tmp/a b.png", nasty])
        #expect(word.bundleID == "com.microsoft.Word")
        let newDocument = OfficeScripts.wordInsert(imagePath: "/tmp/a.png", documentName: nil, lockAspectRatio: false)
        #expect(newDocument.arguments == ["/tmp/a.png", ""])
        let excel = OfficeScripts.excelInsert(imagePath: "/tmp/a.png", workbookName: nil, size: CGSize(width: 320.4, height: 199.6))
        #expect(excel.arguments == ["/tmp/a.png", "", "320", "200"])
        let picture = OfficeScripts.powerPointPicture(presentationName: "Deck", slideIndex: 4, imagePath: "/tmp/a.png",
                                                      frame: CGRect(x: 10.4, y: 20.6, width: 300, height: 200), lockAspectRatio: false)
        #expect(picture.arguments == ["Deck", "4", "/tmp/a.png", "10", "21", "300", "200"])
    }

    @Test func recipientsArePassedOnePerLine() {
        let mail = OfficeScripts.mailNewMessage(imagePath: "/tmp/a.png", subject: "Shot", to: ["a@x.test", "b@x.test"],
                                                cc: [], bcc: ["c@x.test"])
        #expect(mail.arguments == ["/tmp/a.png", "Shot", "a@x.test\nb@x.test", "", "c@x.test"])
        #expect(AppleScriptCall.lines(["a\nb", "c\rd"]) == "a b\nc d")
        #expect(mail.source.contains("paragraphs of item 3 of argv"))
    }

    @Test func optionsChangeTheScript() {
        #expect(OfficeScripts.wordInsert(imagePath: "", documentName: nil, lockAspectRatio: true).source.contains("lock aspect ratio of thePicture to true"))
        #expect(OfficeScripts.wordInsert(imagePath: "", documentName: nil, lockAspectRatio: false).source.contains("lock aspect ratio of thePicture to false"))
        let text = OfficeScripts.outlookNewMail(imagePath: "", subject: "", to: [], cc: [], bcc: [], format: .text)
        let html = OfficeScripts.outlookNewMail(imagePath: "", subject: "", to: [], cc: [], bcc: [], format: .html)
        #expect(text.source.contains("plain text content"))
        #expect(!html.source.contains("plain text content"))
        let slide = OfficeScripts.powerPointSlide(presentationName: nil, layout: .titleOnly, title: "")
        #expect(slide.source.contains("{layout:slide layout title only}"))
        #expect(slide.source.contains("slide layout blank"))
    }

    @Test func slideLayoutNamesFollowPowerPointsDictionary() {
        #expect(OfficeSettings.SlideLayout.allCases.count == 36)
        #expect(OfficeSettings.SlideLayout.pictureWithCaption.appleScriptName == "picture with caption")
        #expect(OfficeSettings.SlideLayout.title.appleScriptName == "title slide")
        #expect(OfficeSettings.SlideLayout.textAndMediaClip.appleScriptName == "media clip")
        #expect(OfficeSettings.SlideLayout.verticalTitleAndTextOverChart.appleScriptName == "vertical title and text over chart")
        #expect(OfficeSettings.SlideLayout.pictureWithCaption.displayName == "Picture with caption")
        #expect(OfficeSettings.SlideLayout.twoColumnText.displayName == "Two column text")
    }

    @Test func failuresFromOsascript() {
        let denied = AppleScriptFailure.parse("102:150: execution error: Not authorized to send Apple events to Microsoft Word. (-1743)\n")
        #expect(denied.number == -1743)
        #expect(denied.kind == .notAllowed)
        #expect(denied.message == "Not authorized to send Apple events to Microsoft Word.")
        #expect(denied.explanation(appName: "Microsoft Word").contains("Privacy & Security › Automation"))
        #expect(AppleScriptFailure.parse("1:2: execution error: x (-1744)").kind == .needsConsent)
        #expect(AppleScriptFailure.parse("1:2: execution error: Application isn’t running. (-600)").kind == .notRunning)
        #expect(AppleScriptFailure.parse("1:2: execution error: AppleEvent timed out. (-1712)").kind == .timedOut)
        #expect(AppleScriptFailure.parse("1:2: execution error: Can’t get document \"x\". (-1728)").kind == .notSupported)
        #expect(AppleScriptFailure.parse("1:2: execution error: x doesn’t understand the “make” message. (-1708)").kind == .notSupported)
        #expect(AppleScriptFailure.parse("1:2: execution error: User canceled. (-128)").kind == .cancelled)
        let odd = AppleScriptFailure.parse("something else")
        #expect(odd.number == nil)
        #expect(odd.kind == .other)
        #expect(odd.message == "something else")
    }

    @Test func listAnswers() {
        #expect(AppleScriptOutput.lines("Doc 1\n Doc  2 \n\n") == ["Doc 1", " Doc  2 "])
        #expect(AppleScriptOutput.lines("") == [])
        let outlook = OfficeScripts.openItems(of: .outlook, fromOutput: "41\tRe: Budget\n42\t\n")
        #expect(outlook == [OfficeOpenItem(id: "41", title: "Re: Budget"), OfficeOpenItem(id: "42", title: "New message")])
        let word = OfficeScripts.openItems(of: .word, fromOutput: "Report.docx\nNotes\n")
        #expect(word.map(\.id) == ["Report.docx", "Notes"])
        #expect(OfficeScripts.openItems(of: .notes) == nil)
    }

    /// DST-127: Outlook's meeting windows (upstream `OutlookAllowExportInMeetings`) come only when allowed.
    @Test func outlookMeetingsOnlyWhenAllowed() {
        let plain = OfficeScripts.outlookOpenMessages()
        let meetings = OfficeScripts.outlookOpenMessages(includeMeetings: true)
        #expect(plain.arguments == ["0"])
        #expect(meetings.arguments == ["1"])
        #expect(plain.source == meetings.source, "fixed text; the switch is an argument")
        #expect(meetings.source.contains("class of theItem is calendar event"))
        #expect(meetings.source.contains("organizer of theItem"))
        #expect(meetings.source.contains("\"event:\""))
        #expect(OfficeScripts.openItems(of: .outlook)?.arguments == ["0"])
        #expect(OfficeScripts.openItems(of: .outlook, outlookMeetings: true)?.arguments == ["1"])
        #expect(OfficeScripts.openItems(of: .word, outlookMeetings: true) == OfficeScripts.wordDocuments())
        let attach = OfficeScripts.outlookAttachToEvent(imagePath: "/tmp/a.png", windowID: "77")
        #expect(attach.arguments == ["/tmp/a.png", "77"])
        #expect(attach.bundleID == "com.microsoft.Outlook")
        #expect(attach.source.contains("make new attachment at theEvent"))
    }

    /// L6: the organizer is the user's only by an account's address or its exact full name, not a part of it.
    @Test func outlookOrganizerIsComparedWhole() {
        let source = OfficeScripts.outlookOpenMessages(includeMeetings: true).source
        #expect(source.contains("theOrganizer is theAddress or theOrganizer contains (\"<\" & theAddress & \">\")"))
        #expect(source.contains("if theOrganizer is (contents of aName) then"))
        #expect(!source.contains("theOrganizer contains aText"))
    }

    /// The security note: window names and Mail subjects lose tabs and line breaks before they join the answer, so a
    /// name can't make a line (an `event:` record) of its own.
    @Test func namesStayOneField() {
        for call in [OfficeScripts.outlookOpenMessages(includeMeetings: true), OfficeScripts.mailOpenMessages()] {
            #expect(call.source.contains("on oneLine(theValue)"))
            #expect(!call.source.contains("tab & (name of aWindow)"))
            #expect(!call.source.contains("tab & (subject of aMessage)"))
        }
    }

    /// Runs the `oneLine` handler itself with `osascript` (no app is involved).
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript")))
    func oneLineHandlerReplacesTabsAndLineBreaks() async throws {
        let source = "on run argv\n    return my oneLine(item 1 of argv)\nend run\n\n" + OfficeScripts.oneLineHandler
        let result = try await offPool { () throws -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-", "a\tb\nevent:9\tforged\rc"]
            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            input.fileHandleForWriting.write(Data(source.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        #expect(result == "a b event:9 forged c\n")
        let items = OfficeScripts.openItems(of: .outlook, fromOutput: "41\t" + result)
        #expect(items == [OfficeOpenItem(id: "41", title: "a b event:9 forged c")])
    }

    @Test func outlookMeetingWindowsParse() {
        let items = OfficeScripts.openItems(of: .outlook, fromOutput: "41\tRe: Budget\nevent:77\tDesign review\nevent:78\t\nevent:\tBroken\n")
        let expected = [OfficeOpenItem(id: "41", title: "Re: Budget"),
                        OfficeOpenItem(id: "77", title: "Design review", isMeeting: true),
                        OfficeOpenItem(id: "78", title: "New meeting", isMeeting: true)]
        #expect(items == expected)
        // Only Outlook marks meetings: Mail's ids are taken as they are.
        let mail = OfficeScripts.openItems(of: .mail, fromOutput: "event:5\tSubject\n")
        #expect(mail == [OfficeOpenItem(id: "event:5", title: "Subject")])
        #expect(!OfficeOpenItem(id: "1", title: "x").isMeeting)
    }

    @Test func applicationsAndDestinations() {
        #expect(OfficeApplication(destination: .word) == .word)
        #expect(OfficeApplication(destination: .email) == nil)
        #expect(OfficeApplication(destination: .clipboard) == nil)
        #expect(OfficeApplication.mail.destination == .email)
        #expect(!OfficeApplication.notes.hasOpenItems)
        #expect(OfficeApplication.powerpoint.bundleID == "com.microsoft.Powerpoint")
    }

    // Compile checks: the scripts against the dictionaries of the installed apps.

    @Test(.enabled(if: canCompile), arguments: OfficeApplication.allCases)
    func scriptsCompileAgainstTheInstalledApp(app: OfficeApplication) async throws {
        guard isInstalled(app.bundleID) else { return }
        for call in Self.allCalls() where call.bundleID == app.bundleID {
            let error = try await compileError(call.source)
            #expect(error == nil, "\(app.name): \(error ?? "")\n\(call.source)")
        }
    }

    @Test func browserScriptsAreFixedText() {
        #expect(ScriptableBrowser.all.count == 7)
        for browser in ScriptableBrowser.all {
            let call = browser.tabURLsScript
            #expect(call.arguments.isEmpty)
            #expect(call.bundleID == browser.bundleID)
            #expect(call.source.contains("tell application id \"\(browser.bundleID)\""))
            let ascii = call.source.unicodeScalars.allSatisfy { $0.isASCII }
            #expect(ascii)
        }
    }

    @Test(.enabled(if: canCompile))
    func browserScriptsCompileAgainstTheInstalledBrowsers() async throws {
        for browser in ScriptableBrowser.all where isInstalled(browser.bundleID) {
            let error = try await compileError(browser.tabURLsScript.source)
            #expect(error == nil, "\(browser.name): \(error ?? "")")
        }
    }

    @Test(.enabled(if: canCompile && isInstalled("com.microsoft.Powerpoint")))
    func everySlideLayoutIsInPowerPointsDictionary() async throws {
        let names = OfficeSettings.SlideLayout.allCases.map { "slide layout " + $0.appleScriptName }.joined(separator: ", ")
        let source = "tell application id \"com.microsoft.Powerpoint\"\n    set layouts to {\(names)}\nend tell\n"
        let error = try await compileError(source)
        #expect(error == nil, "\(error ?? "")")
    }
}

struct OfficeLayoutTests {
    private let slide = PowerPointSlide(presentationName: "Deck", index: 2, slideSize: CGSize(width: 960, height: 540),
                                        placeholder: CGRect(x: 100, y: 50, width: 400, height: 300))

    @Test func smallPictureIsCentredInThePlaceholder() {
        let frame = OfficeLayout.pictureFrame(imageSize: CGSize(width: 200, height: 100), slide: slide)
        #expect(frame == CGRect(x: 200, y: 150, width: 200, height: 100))
    }

    @Test func widePictureShrinksToThePlaceholderKeepingItsShape() {
        let frame = OfficeLayout.pictureFrame(imageSize: CGSize(width: 800, height: 300), slide: slide)
        #expect(frame.width == 400)
        #expect(frame.height == 150)
        #expect(frame.minX == 100)
        #expect(frame.midY == 200)
    }

    @Test func withoutAPlaceholderTheSlideCentres() {
        var blank = slide
        blank.placeholder = nil
        let frame = OfficeLayout.pictureFrame(imageSize: CGSize(width: 1920, height: 1080), slide: blank)
        #expect(frame == CGRect(x: 0, y: 0, width: 960, height: 540))
        let small = OfficeLayout.pictureFrame(imageSize: CGSize(width: 100, height: 40), slide: blank)
        #expect(small == CGRect(x: 430, y: 250, width: 100, height: 40))
    }

    @Test func slideAnswerParses() {
        let parsed = PowerPointSlide(output: "Presentation1\t3\t960\t540\t100\t50\t400\t300\n")
        #expect(parsed == slide.withName("Presentation1", index: 3))
        let blank = PowerPointSlide(output: "Deck\t1\t720\t540")
        #expect(blank?.placeholder == nil)
        #expect(blank?.slideSize == CGSize(width: 720, height: 540))
        #expect(PowerPointSlide(output: "") == nil)
        #expect(PowerPointSlide(output: "Deck\tx\t1\t2") == nil)
    }

    @Test func picturesInPointsAndTheirFormat() {
        #expect(OfficeLayout.pointSize(pixelWidth: 1280, pixelHeight: 800, scale: 2) == CGSize(width: 640, height: 400))
        #expect(OfficeLayout.pointSize(pixelWidth: 10, pixelHeight: 10, scale: 0) == CGSize(width: 10, height: 10))
        #expect(OfficeLayout.fileFormat(for: .jpg) == .jpg)
        #expect(OfficeLayout.fileFormat(for: .webp) == .png)
        #expect(OfficeLayout.fileFormat(for: .pdf) == .png)
    }

    @Test func attachmentNamesAreClean() {
        #expect(OfficeLayout.attachmentName(title: "  Safari – Budget (2026)! ") == "Safari  Budget 2026")
        #expect(OfficeLayout.attachmentName(title: "???") == "Greenshot Capture")
        #expect(OfficeLayout.attachmentName(title: "Übersicht_1") == "Übersicht_1")
    }
}

private extension PowerPointSlide {
    func withName(_ name: String, index: Int) -> PowerPointSlide {
        var copy = self
        copy.presentationName = name
        copy.index = index
        return copy
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The unsaved editors kept for the next start (upstream Restart Manager state files).
struct EditorSessionTests {
    static func temporaryStore() -> EditorSessionStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorSessionTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(EditorSessionStore.folderName, isDirectory: true)
        return EditorSessionStore(folder: folder)
    }

    static func sessionFile(_ reason: GreenshotFile.Session.Reason = .autosave, original: String? = "/tmp/shot.png") throws -> Data {
        let session = GreenshotFile.Session(reason: reason, originalFile: original)
        let element = Annotation(kind: .arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 20, y: 25))
        return try GreenshotFile.Contents(image: GreenshotFileTests.background, scale: 2, elements: [element], counterStart: 4,
                                          title: "Mail", captureDate: Date(timeIntervalSinceReferenceDate: 50),
                                          session: session).encoded()
    }

    @Test func writeListReadRemove() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        let id = UUID()
        try store.write(try Self.sessionFile(.quit), for: id)
        #expect(store.saved() == [store.url(for: id)])
        let contents = try #require(GreenshotFile.read(contentsOf: store.url(for: id)))
        #expect(contents.session == GreenshotFile.Session(reason: .quit, originalFile: "/tmp/shot.png"))
        #expect(contents.title == "Mail")
        #expect(contents.counterStart == 4)
        #expect(contents.elements.map(\.kind) == [.arrow])
        store.remove(id)
        #expect(store.saved().isEmpty)
    }

    @Test func filesAreTheUsersOnly() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        let id = UUID()
        try store.write(try Self.sessionFile(), for: id)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url(for: id).path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
    }

    /// Two copies of the app (process 100 and 200) with the same folder.
    static func twoCopies() -> (first: EditorSessionStore, second: EditorSessionStore) {
        let first = EditorSessionStore(folder: temporaryStore().folder, process: 100)
        return (first, EditorSessionStore(folder: first.folder, process: 200))
    }

    @MainActor @Test func forgetAllLeavesTheFilesOfAnotherCopy() throws {
        let (mine, other) = Self.twoCopies()
        defer { try? FileManager.default.removeItem(at: mine.folder.deletingLastPathComponent()) }
        try other.write(try Self.sessionFile(), for: UUID())
        let note = mine.folder.appendingPathComponent("note.txt")
        try Data("keep".utf8).write(to: note)
        let book = EditorSessionBook(store: mine)
        let document = EditorDocument(image: GreenshotFileTests.background, scale: 2, title: "Mine")
        #expect(book.write(document, reason: .autosave, wait: true))
        #expect(mine.saved().count == 2)
        book.forgetAll()
        let left = mine.saved()
        #expect(left.count == 1)
        #expect(left.first.flatMap(EditorSessionStore.owner(of:)) == 200)
        #expect(FileManager.default.fileExists(atPath: note.path))
    }

    @Test func filesOfARunningCopyAreNotRestored() throws {
        let (mine, other) = Self.twoCopies()
        defer { try? FileManager.default.removeItem(at: mine.folder.deletingLastPathComponent()) }
        let id = UUID()
        try other.write(try Self.sessionFile(), for: id)
        let claimed = try #require(other.claim(other.url(for: id)))
        try other.write(try Self.sessionFile(), for: UUID())
        let running: (Int32) -> Bool = { $0 == 200 }
        #expect(mine.saved(isRunning: running).isEmpty)
        #expect(mine.unfinishedRestores(isRunning: running).isEmpty)
        // Once that copy ended, its files are this one's to restore (or to send to the Trash).
        #expect(mine.saved().count == 1)
        #expect(mine.unfinishedRestores() == [claimed])
    }

    @Test func namesCarryTheProcess() throws {
        let store = EditorSessionStore(folder: Self.temporaryStore().folder, process: 4321)
        let id = UUID()
        #expect(store.url(for: id).lastPathComponent == "\(id.uuidString).4321.greenshot")
        #expect(EditorSessionStore.owner(of: store.url(for: id)) == 4321)
        #expect(EditorSessionStore.owner(of: URL(fileURLWithPath: "/x/\(id.uuidString).greenshot")) == nil)
        // A claimed file is this process's while it is restored.
        let other = EditorSessionStore(folder: store.folder, process: 99)
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        try other.write(try Self.sessionFile(), for: id)
        let claimed = try #require(store.claim(other.url(for: id)))
        #expect(EditorSessionStore.owner(of: claimed) == 4321)
    }

    @Test func restoredFileStaysUnfinishedUntilSettled() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        let id = UUID()
        try store.write(try Self.sessionFile(), for: id)
        let claimed = try #require(store.claim(store.url(for: id)))
        #expect(store.saved().isEmpty)
        #expect(store.unfinishedRestores() == [claimed])
        let newID = UUID()
        #expect(store.adopt(claimed, as: newID))
        // Opened, but a crash now (e.g. while it is first drawn) must not reopen it at the next start.
        #expect(store.saved().isEmpty)
        #expect(store.unfinishedRestores() == [store.restoringURL(for: newID)])
        store.settle(newID)
        #expect(store.unfinishedRestores().isEmpty)
        #expect(store.saved() == [store.url(for: newID)])
    }

    @Test func writingARestoredDocumentSettlesIt() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        let id = UUID()
        try store.write(try Self.sessionFile(), for: id)
        let claimed = try #require(store.claim(store.url(for: id)))
        let newID = UUID()
        #expect(store.adopt(claimed, as: newID))
        try store.write(try Self.sessionFile(), for: newID)
        #expect(store.unfinishedRestores().isEmpty)
        #expect(store.saved() == [store.url(for: newID)])
        store.remove(newID)
        #expect(store.saved().isEmpty)
    }

    @MainActor @Test func bookSettlesRestoredDocumentsLater() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        try store.write(try Self.sessionFile(), for: UUID())
        let kept = try #require(store.saved().first)
        let claimed = try #require(store.claim(kept))
        let book = EditorSessionBook(store: store)
        let document = EditorDocument(image: GreenshotFileTests.background, scale: 2, title: "Restored")
        #expect(book.adopt(claimed, for: document))
        #expect(book.hasFile(document.id))
        #expect(!book.needsWrite(document))
        #expect(store.saved().isEmpty)
        book.settle()
        book.waitForDisk()
        #expect(store.saved() == [store.url(for: document.id)])
        book.forget(document.id)
        book.waitForDisk()
        #expect(store.saved().isEmpty)
    }

    @Test func oldestFirst() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.folder.deletingLastPathComponent()) }
        let older = UUID()
        let newer = UUID()
        try store.write(try Self.sessionFile(), for: newer)
        try store.write(try Self.sessionFile(), for: older)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                                              ofItemAtPath: store.url(for: older).path)
        #expect(store.saved() == [store.url(for: older), store.url(for: newer)])
    }

    @Test func folderFollowsTheSettingsDirectory() {
        let support = URL(fileURLWithPath: "/Users/me/Library/Application Support")
        let standard = EditorSessionStore.folder(settingsDirectory: nil, applicationSupport: support, bundleIdentifier: "app.id")
        #expect(standard.path == "/Users/me/Library/Application Support/app.id/Unsaved Editors")
        let portable = EditorSessionStore.folder(settingsDirectory: URL(fileURLWithPath: "/Volumes/Stick/Greenshot"),
                                                 applicationSupport: support, bundleIdentifier: "app.id")
        #expect(portable.path == "/Volumes/Stick/Greenshot/Unsaved Editors")
    }

    // MARK: When quitting keeps the editors

    @Test func fourCharacterCodes() {
        #expect(EditorSessionPolicy.code("logo") == 0x6C6F_676F)
        #expect(EditorSessionPolicy.code("why?") == 0x7768_793F)
    }

    @Test(arguments: ["logo", "rlgo", "rrst", "rsdn", "rest", "shut", "quia"])
    func endOfTheSessionKeeps(_ reason: String) {
        let code = EditorSessionPolicy.code(reason)
        #expect(EditorSessionPolicy.keepsEditors(quitReason: code, poweringOffSince: nil, now: Date(), keepsWindows: false))
    }

    @Test func plainQuitAsks() {
        let now = Date()
        #expect(!EditorSessionPolicy.keepsEditors(quitReason: nil, poweringOffSince: nil, now: now, keepsWindows: false))
        let other = EditorSessionPolicy.code("abcd")
        #expect(!EditorSessionPolicy.keepsEditors(quitReason: other, poweringOffSince: nil, now: now, keepsWindows: false))
    }

    @Test func powerOffCountsForAMinute() {
        let now = Date()
        let recent = now.addingTimeInterval(-10)
        let old = now.addingTimeInterval(-120)
        #expect(EditorSessionPolicy.keepsEditors(quitReason: nil, poweringOffSince: recent, now: now, keepsWindows: false))
        #expect(!EditorSessionPolicy.keepsEditors(quitReason: nil, poweringOffSince: old, now: now, keepsWindows: false))
    }

    @Test func keepWindowsSettingKeeps() {
        #expect(EditorSessionPolicy.keepsEditors(quitReason: nil, poweringOffSince: nil, now: Date(), keepsWindows: true))
    }
}
